# ── dbt-dev (shared Coder module) ─────────────────────────────────────────────
# Rendered by Terraform templatefile() and interpolated into the template's
# startup_script. Runs in a subshell so its exits can't abort the outer script.
(
set -uo pipefail

log() { echo "[dbt-dev] $*"; }

# ── VERSION STAMP — update this string on every deploy to confirm new code ran ──
log "=== dbt-dev START 2026-11-16-v4 ==="

CONFIG_B64='${config_b64}'

mkdir -p "$HOME/.init" "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"

log "config_b64 length: $${#CONFIG_B64}"

if ! command -v python3 >/dev/null 2>&1; then
  log "python3 not found; cannot run dbt-dev setup."
  exit 1
fi

CONFIG_FILE="$(mktemp)"
trap 'rm -f "$CONFIG_FILE"' EXIT
echo "$CONFIG_B64" | base64 -d > "$CONFIG_FILE" || { log "FATAL: base64 decode failed"; exit 1; }
chmod 600 "$CONFIG_FILE"
log "config written to $CONFIG_FILE ($(wc -c < "$CONFIG_FILE") bytes)"

cfg() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))[sys.argv[2]]; print(v if isinstance(v,str) else json.dumps(v))' "$CONFIG_FILE" "$1"; }

# ── 1. dbt Fusion ─────────────────────────────────────────────────────────────
if [ "$(cfg install_dbt_fusion)" = "true" ]; then
  _ver="$(cfg dbt_fusion_version)"
  if [ -n "$_ver" ]; then
    _installed="$("$HOME/.local/bin/dbtf" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
    if [ "$_installed" = "$_ver" ]; then
      log "dbt-fusion $_ver already installed, skipping."
    else
      log "Installing dbt-fusion $_ver..."
      curl -fsSL https://public.cdn.getdbt.com/fs/install/install.sh | sh -s -- --version "$_ver" || log "dbt-fusion install failed, continuing..."
      grep -q '\.local/bin' ~/.bashrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    fi
  else
    if [ ! -x "$HOME/.local/bin/dbtf" ]; then
      log "Installing dbt-fusion (latest)..."
      curl -fsSL https://public.cdn.getdbt.com/fs/install/install.sh | sh -s -- --update || log "dbt-fusion install failed, continuing..."
      grep -q '\.local/bin' ~/.bashrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    else
      log "dbt-fusion already installed, skipping."
    fi
  fi
  export PATH="$HOME/.local/bin:$PATH"
  # dbt Fusion 2.x installs the binary as "dbt"; normalise to "dbtf" so the
  # rest of this script and all generated wrappers use a consistent name.
  if [ -x "$HOME/.local/bin/dbt" ] && [ ! -x "$HOME/.local/bin/dbtf" ]; then
    mv "$HOME/.local/bin/dbt" "$HOME/.local/bin/dbtf"
    log "Renamed ~/.local/bin/dbt → dbtf"
  fi
  "$HOME/.local/bin/dbtf" --version 2>/dev/null || log "dbtf not found in PATH"
fi

# ── 2. Python dbt adapters ────────────────────────────────────────────────────
# Installs each entry from the adapters list into an isolated venv and creates
# a named CLI command in ~/.local/bin that sets DBT_PROJECT_DIR automatically.
_adapters_err=""
# Use \x01 (ASCII SOH) as field separator — tab is IFS whitespace so consecutive
# empty tabs collapse, causing fields to shift. \x01 is never whitespace.
_adapters_out=$(python3 -c "
import json, sys
sep = '\x01'
for a in json.load(open(sys.argv[1])).get('adapters', []):
    print(sep.join([
        a['type'],
        a.get('core_version') or '',
        a.get('adapter_version') or '',
        a.get('venv_path') or '',
        a.get('command') or '',
        a.get('project_dir') or '',
    ]))
" "$CONFIG_FILE" 2>&1) || { _adapters_err="$_adapters_out"; _adapters_out=""; }
[ -n "$_adapters_err" ] && log "adapters parse error: $_adapters_err"
log "adapters_out=$(printf '%s' "$_adapters_out" | wc -l) lines"
[ -z "$_adapters_out" ] && log "WARNING: no adapters found in config — wrappers will not be created"

if [ -n "$_adapters_out" ]; then
  _sep=$(printf '\001')
  # Write to a temp file so the while loop runs in the current shell, not a
  # pipeline subshell. This prevents set -e from killing the loop on venv errors.
  _adapters_tmp=$(mktemp)
  printf '%s\n' "$_adapters_out" > "$_adapters_tmp"
  while IFS="$_sep" read -r _type _core_ver _adapter_ver _venv _cmd _proj; do
    [ -z "$_type" ] && continue
    # Default venv: .venv inside project dir if set, else ~/.venvs/dbt-{type}
    [ -z "$_venv" ] && [ -n "$_proj" ] && _venv="$_proj/.venv"
    [ -z "$_venv" ] && _venv="$HOME/.venvs/dbt-$_type"
    _cmd="$${_cmd:-dbt-$_type}"
    _core_pkg="dbt-core$${_core_ver:+~=$_core_ver}"
    _adapter_pkg="dbt-$_type$${_adapter_ver:+~=$_adapter_ver}"
    _wrapper="$HOME/.local/bin/$_cmd"
    log "Processing adapter: type=$_type cmd=$_cmd proj=$_proj"
    if [ "$_type" = "fusion" ]; then
      # No venv — wrap the Fusion binary (dbtf) already installed in step 1.
      if [ -n "$_proj" ]; then
        printf '#!/bin/sh\nexec "$HOME/.local/bin/dbtf" --project-dir "%s" "$@"\n' \
          "$_proj" > "$_wrapper"
      else
        printf '#!/bin/sh\nexec "$HOME/.local/bin/dbtf" "$@"\n' > "$_wrapper"
      fi
      chmod +x "$_wrapper"
      log "Command '$_cmd' created (fusion wrapper$${_proj:+, project: $_proj})"
    else
      # Create wrapper first so the command always exists even if install hangs/fails.
      # Use `cd` instead of --project-dir: more compatible across dbt-core versions.
      if [ -n "$_proj" ]; then
        printf '#!/bin/sh\ncd "%s" || exit 1\nexec "%s/bin/dbt" "$@"\n' \
          "$_proj" "$_venv" > "$_wrapper"
      else
        printf '#!/bin/sh\nexec "%s/bin/dbt" "$@"\n' "$_venv" > "$_wrapper"
      fi
      chmod +x "$_wrapper"
      log "Command '$_cmd' created (venv: $_venv$${_proj:+, project: $_proj})"
      # Install venv only if the dbt binary isn't already present.
      if [ -x "$_venv/bin/dbt" ]; then
        log "dbt-$_type already installed at $_venv, skipping."
      else
        log "Installing dbt-$_type venv at $_venv..."
        mkdir -p "$_venv"
        python3 -m venv "$_venv" || { log "dbt-$_type venv creation failed, continuing..."; true; }
        "$_venv/bin/pip" install --quiet --upgrade pip || true
        "$_venv/bin/pip" install --quiet "$_core_pkg" "$_adapter_pkg" || log "dbt-$_type install failed, continuing..."
        log "dbt-$_type installed."
      fi
      "$_venv/bin/dbt" --version 2>/dev/null | head -1 || log "dbt-$_type venv dbt not found"
    fi
  done < "$_adapters_tmp"
  rm -f "$_adapters_tmp"
  log "step 2 complete — ls ~/.local/bin/dbt*: $(ls ~/.local/bin/dbt* 2>/dev/null | tr '\n' ' ' || echo 'none')"
fi

# ── 3. dbt-graphify ───────────────────────────────────────────────────────────
_ver="$(cfg dbt_graphify_version)"
_installed="$(dbt-graphify --version 2>/dev/null || true)"
if [ "$_installed" != "$_ver" ]; then
  log "Installing dbt-graphify $_ver..."
  pipx install --force "dbt-graphify==$_ver" || log "dbt-graphify install failed, continuing..."
else
  log "dbt-graphify $_ver already installed, skipping."
fi
dbt-graphify --version 2>/dev/null || log "dbt-graphify not found in PATH"

# ── 4. dbt-graphify watch ─────────────────────────────────────────────────────
_manifest="$(cfg dbt_graphify_watch_manifest)"
_out="$(cfg dbt_graphify_watch_out)"

if [ -n "$_manifest" ] && command -v dbt-graphify >/dev/null 2>&1; then
  _log="$HOME/.cache/dbt-graphify-watch.log"
  _pid="$HOME/.cache/dbt-graphify-watch.pid"
  if [ -f "$_pid" ]; then
    kill "$(cat "$_pid")" 2>/dev/null || true
    rm -f "$_pid"
  fi
  mkdir -p "$(dirname "$_log")"
  PYTHONUNBUFFERED=1 nohup dbt-graphify "$_manifest" --out "$_out" --watch \
    > "$_log" 2>&1 &
  echo $! > "$_pid"
  log "watch started (manifest: $_manifest, out: $_out)"
fi

# ── 5. dbt-wizard ─────────────────────────────────────────────────────────────
if [ "$(cfg install_wizard)" = "true" ]; then
  if ! command -v wizard >/dev/null 2>&1; then
    log "Installing dbt-wizard..."
    curl -fsSL https://public.cdn.getdbt.com/dbt-wizard/install/install-wizard.sh | sh \
      || log "wizard install failed, continuing..."
  else
    log "dbt-wizard already installed, skipping."
  fi
  wizard --version 2>/dev/null || log "wizard not found in PATH"
fi

# ── 6. uv / uvx (dbt MCP server runtime) ─────────────────────────────────────
if [ "$(cfg install_uv)" = "true" ]; then
  if ! command -v uvx >/dev/null 2>&1; then
    log "Installing uv..."
    pipx install uv || log "uv install failed, continuing..."
  else
    log "uv already installed, skipping."
  fi
fi

# ── 7. dbt Cloud credentials ──────────────────────────────────────────────────
_dbt_cloud_yml="$(cfg dbt_cloud_yml)"
if [ -n "$_dbt_cloud_yml" ]; then
  log "Writing dbt Cloud credentials..."
  mkdir -p ~/.dbt
  printf '%s\n' "$_dbt_cloud_yml" > ~/.dbt/dbt_cloud.yml
  chmod 600 ~/.dbt/dbt_cloud.yml
else
  log "No dbt Cloud credentials provided, skipping ~/.dbt/dbt_cloud.yml."
fi

# ── 8. sqltools-trino extraCredential patch (background) ──────────────────────
# Patches the bundled plugin.js to forward trinoOptions.extraCredential to
# trino-client (encodes as X-Trino-Extra-Credential header). Runs in the
# background because code-server installs extensions after this script starts.
if [ "$(cfg patch_sqltools_trino)" = "true" ]; then
  (
    for i in $(seq 1 60); do
      PLUGIN=$(ls ~/.local/share/code-server/extensions/akhilputhiry.sqltools-trino-driver-*/out/ls/plugin.js 2>/dev/null | head -1)
      if [ -n "$PLUGIN" ]; then
        if grep -q 'extraCredential:this.credentials' "$PLUGIN"; then
          log "Trino driver already patched for extraCredential."
        elif grep -q 'source:"sqltools-driver"' "$PLUGIN"; then
          sed -i 's/source:"sqltools-driver"/source:"sqltools-driver",extraCredential:this.credentials.trinoOptions?.extraCredential/' "$PLUGIN"
          log "Trino driver patched for extraCredential."
        else
          log "WARNING: Trino driver bundle layout changed; extraCredential patch NOT applied."
        fi
        break
      fi
      sleep 10
    done
  ) &
fi

# ── 9. VS Code snippets ───────────────────────────────────────────────────────
# Written to the code-server USER profile (snippets only load from there, not
# from Machine). Overwritten on every start so template updates propagate.
if [ "$(cfg install_snippets)" = "true" ]; then
  mkdir -p ~/.local/share/code-server/User/snippets
  cat > ~/.local/share/code-server/User/snippets/dbt.code-snippets << 'SNIPPETS_EOF'
{
  "__block": {
    "scope": "jinja-sql,sql,jinja",
    "prefix": "__block",
    "body": ["{% block $${1:name} %}", "    $${0}", "{% endblock %}"],
    "description": "Jinja block"
  },
  "__config": {
    "scope": "jinja-sql,sql,jinja",
    "prefix": "__config",
    "body": ["{{", "    config(", "        materialized='$${1:table}'", "    )", "}}", "$${0}"],
    "description": "dbt config block"
  },
  "__config_incremental": {
    "scope": "jinja-sql,sql,jinja",
    "prefix": "__config_incremental",
    "body": ["{{", "    config(", "        materialized='incremental',", "        unique_key='$${1:id}'", "    )", "}}", "$${0}"],
    "description": "dbt incremental config block"
  },
  "__config_redshift": {
    "scope": "jinja-sql,sql,jinja",
    "prefix": "__config_redshift",
    "body": ["{{", "    config(", "        materialized='table',", "        sort_type='interleaved',", "        sort=['$${1:sort_key}'],", "        dist='$${2:dist_key}'", "    )", "}}", "$${0}"],
    "description": "dbt Redshift config block"
  },
  "__do": {
    "scope": "jinja-sql,sql,jinja",
    "prefix": "__do",
    "body": ["{% do $${0} %}"],
    "description": "Jinja do statement"
  },
  "__doc": {
    "scope": "jinja-sql,sql,jinja",
    "prefix": "__doc",
    "body": ["\"{{ doc('$${1:doc_name}') }}\"$${0}"],
    "description": "dbt doc reference"
  },
  "__docs": {
    "scope": "jinja-sql,sql,jinja",
    "prefix": "__docs",
    "body": ["{% docs $${1:name} %}", "    $${0}", "{% enddocs %}"],
    "description": "dbt docs block"
  },
  "__env_var": {
    "scope": "jinja-sql,sql,jinja",
    "prefix": "__env_var",
    "body": ["{{ env_var('$${1:env_var_name}') }}$${0}"],
    "description": "dbt env_var"
  },
  "__for": {
    "scope": "jinja-sql,sql,jinja",
    "prefix": "__for",
    "body": ["{% for $${1:item} in $${2:sequence} %}", "    $${0}", "{% endfor %}"],
    "description": "Jinja for loop"
  },
  "__if": {
    "scope": "jinja-sql,sql,jinja",
    "prefix": "__if",
    "body": ["{% if $${1:expr} %}", "    $${0}", "{% endif %}"],
    "description": "Jinja if block"
  },
  "__if_incremental": {
    "scope": "jinja-sql,sql,jinja",
    "prefix": "__if_incremental",
    "body": ["{% if is_incremental() %}", "    -- this filter will only be applied on an incremental run", "    where $${1:event_time} > (select max($${1:event_time}) from {{ this }})", "{% endif %}", "$${0}"],
    "description": "dbt is_incremental filter"
  },
  "__macro": {
    "scope": "jinja-sql,sql,jinja",
    "prefix": "__macro",
    "body": ["{% macro $${1:name}($${2:args}) %}", "    $${0}", "{% endmacro %}"],
    "description": "dbt macro"
  },
  "__ref": {
    "scope": "jinja-sql,sql,jinja",
    "prefix": "__ref",
    "body": ["{{ ref('$${1:model_name}') }}$${0}"],
    "description": "dbt ref"
  },
  "__snapshot": {
    "scope": "jinja-sql,sql,jinja",
    "prefix": "__snapshot",
    "body": ["{% snapshot $${1:snapshot_name} %}", "    {{", "        config(", "            target_schema='$${2:schema}',", "            target_database='$${3:database}',", "            unique_key='$${4:field}',", "            strategy='timestamp',", "            invalidate_hard_deletes=False,", "            updated_at='$${5:updated_at_field}'", "        )", "    }}", "", "    select * from {{ source('$${6:source_name}', '$${7:object_name}') }}", "{% endsnapshot %}", "$${0}"],
    "description": "dbt snapshot"
  },
  "__source": {
    "scope": "jinja-sql,sql,jinja",
    "prefix": "__source",
    "body": ["{{ source('$${1:source_name}', '$${2:object_name}') }}$${0}"],
    "description": "dbt source"
  }
}
SNIPPETS_EOF
  log "dbt snippets written."
fi

# ── 10. Cleanup legacy dispatcher ────────────────────────────────────────────
# Remove old dbt() shell functions and global exports left by previous template
# versions. Named wrapper scripts in ~/.local/bin replace them.
if grep -q '^dbt() {' ~/.bashrc 2>/dev/null; then
  sed -i '/^dbt() {/,/^}/d; /^dbtf() {/,/^}/d; /^tdbt() {/,/^}/d' ~/.bashrc
fi
sed -i '/export DBT_PROJECT_DIR=/d; /export DBT_PROFILES_DIR=/d; /dbt-wrappers\.sh/d' ~/.bashrc

# ── 11. Project .env ──────────────────────────────────────────────────────────
# Writes KEY='VALUE' lines from project_env_vars to {project_dir}/.env.
# dbt Fusion (and the VS Code dbt extension) auto-loads .env from the project root.
export _DBT_ENV_CFG="$CONFIG_FILE"
_project_dir="$(cfg project_dir)"
if [ -n "$_project_dir" ] && [ -d "$_project_dir" ]; then
  export _DBT_ENV_DEST="$_project_dir/.env"
  python3 << 'PYEOF'
import json, os
evars = json.load(open(os.environ['_DBT_ENV_CFG'])).get('project_env_vars', {})
lines = [k + "='" + v.replace("'", "'\\''") + "'" for k, v in evars.items()]
with open(os.environ['_DBT_ENV_DEST'], 'w') as f:
    f.write('\n'.join(lines) + ('\n' if lines else ''))
os.chmod(os.environ['_DBT_ENV_DEST'], 0o600)
PYEOF
  log "Written project .env to $_project_dir/.env."
  _gitignore="$(cfg gitignore_file)"
  if [ -n "$_gitignore" ] && [ -f "$_gitignore" ]; then
    grep -qx '.env' "$_gitignore" || echo '.env' >> "$_gitignore"
  fi
fi

# ── 12. profiles.yml symlink ──────────────────────────────────────────────────
if [ -n "$_project_dir" ] && [ -f "$_project_dir/profiles.yml" ]; then
  mkdir -p ~/.dbt
  ln -sf "$_project_dir/profiles.yml" ~/.dbt/profiles.yml
  log "Symlinked profiles.yml → ~/.dbt/profiles.yml."
fi

# ── 13. dbt deps ──────────────────────────────────────────────────────────────
if [ -n "$_project_dir" ] && [ -f "$_project_dir/dbt_project.yml" ]; then
  log "Installing/updating dbt dependencies..."
  "$HOME/.local/bin/dbt" deps --project-dir "$_project_dir" || log "dbt deps failed, continuing..."
fi

log "=== dbt-dev END 2026-11-16-v4 ==="
) || echo "[dbt-dev] setup failed, continuing..."
export PATH="$HOME/.local/bin:$PATH"
# ── end dbt-dev ───────────────────────────────────────────────────────────────
