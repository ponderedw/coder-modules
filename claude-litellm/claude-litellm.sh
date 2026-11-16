# ── claude-litellm (shared Coder module) ─────────────────────────────────────
# Rendered by Terraform templatefile() and interpolated into the template's
# startup_script. Runs in a subshell so its `exit`s and shell options can't
# end or change the surrounding startup script; a failure is logged, never
# fatal. Dollar-brace sequences are Terraform interpolations.
(
set -uo pipefail

log() { echo "[claude-litellm] $*"; }

CLAUDE_VERSION="${claude_code_version}"
INSTALL_CLI="${install_cli}"
CONFIG_B64='${config_b64}'

mkdir -p "$HOME/.init" "$HOME/.local/bin" "$HOME/.claude" "$HOME/.config"
export PATH="$HOME/.local/bin:$PATH"

if ! command -v python3 >/dev/null 2>&1; then
  log "python3 not found; cannot write Claude Code config."
  exit 1
fi

CONFIG_FILE="$(mktemp)"
trap 'rm -f "$CONFIG_FILE"' EXIT
echo "$CONFIG_B64" | base64 -d > "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

cfg() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))[sys.argv[2]]; print(v if isinstance(v,str) else json.dumps(v))' "$CONFIG_FILE" "$1"; }

# ── 1. Claude Code CLI (pinned) ─────────────────────────────────────────────
if [ "$INSTALL_CLI" = "true" ]; then
  installed="$(cat "$HOME/.init/claude-version" 2>/dev/null || true)"
  if [ "$installed" != "$CLAUDE_VERSION" ] || [ ! -x "$HOME/.local/bin/claude" ]; then
    log "Installing Claude Code CLI v$CLAUDE_VERSION..."
    if curl -fsSL https://claude.ai/install.sh | bash -s "$CLAUDE_VERSION"; then
      echo "$CLAUDE_VERSION" > "$HOME/.init/claude-version"
    else
      log "Claude Code CLI install failed; will retry on next start."
    fi
  else
    log "Claude Code CLI v$CLAUDE_VERSION already installed, skipping."
  fi
  claude --version || log "claude not found in PATH, check install logs above"
fi

# ── 2. Plugins (install on first start, update afterwards) ──────────────────
if command -v claude >/dev/null 2>&1; then
  plugin_list="$(claude plugin list 2>/dev/null || true)"
  python3 -c '
import json, sys
for p in json.load(open(sys.argv[1]))["plugins"]:
    print(p["marketplace_source"], p["marketplace_name"], p["plugin"], sep="\t")
' "$CONFIG_FILE" | while IFS=$'\t' read -r source market plugin; do
    if ! grep -q "$plugin@$market" <<<"$plugin_list"; then
      log "Installing plugin $plugin@$market..."
      claude plugin marketplace add "$source" || log "marketplace add $source failed, continuing..."
      claude plugin install "$plugin@$market" || log "plugin install $plugin@$market failed, continuing..."
    else
      claude plugin marketplace update "$market" || log "marketplace update $market failed, continuing..."
    fi
  done
fi

# ── 3. MCP servers → ~/.claude.json (merge, don't overwrite) ────────────────
python3 - "$CONFIG_FILE" "$HOME/.claude.json" <<'PY'
import json, os, sys
servers = json.load(open(sys.argv[1]))["mcp_servers"] or {}
path = sys.argv[2]
if not servers:
    sys.exit(0)
try:
    with open(path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
data.setdefault("mcpServers", {}).update(servers)
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
os.chmod(tmp, 0o600)
os.replace(tmp, path)
print("[claude-litellm] MCP servers configured: " + ", ".join(servers))
PY

# ── 4. LiteLLM settings ─────────────────────────────────────────────────────
TOKEN="$(cfg token)"
if [ -z "$TOKEN" ]; then
  log "No LiteLLM token provided, skipping Claude Code LiteLLM configuration."
  exit 0
fi

# 4a. User-scope Claude Code settings (CLI + VS Code extension).
python3 - "$CONFIG_FILE" "$HOME/.claude/settings.json" <<'PY'
import json, os, sys
cfg = json.load(open(sys.argv[1]))
path = sys.argv[2]
try:
    with open(path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
data.setdefault("env", {}).update(cfg["settings_env"])
data.setdefault("modelOverrides", {}).update(cfg["model_overrides"])
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
os.chmod(tmp, 0o600)
os.replace(tmp, path)
PY

# 4b. Remove managed keys from settings files left by older template versions
# (a project-level settings.local.json would otherwise win over user scope).
python3 - "$CONFIG_FILE" <<'PY'
import json, os, sys
cfg = json.load(open(sys.argv[1]))
managed = set(cfg["settings_env"])
for raw in cfg["legacy_settings_files"]:
    path = os.path.expanduser(raw)
    if not os.path.isfile(path):
        continue
    try:
        with open(path) as f:
            data = json.load(f)
    except json.JSONDecodeError:
        continue
    env = data.get("env", {})
    for k in managed:
        env.pop(k, None)
    if not env:
        data.pop("env", None)
    if data.get("modelOverrides") == cfg["model_overrides"]:
        data.pop("modelOverrides")
    if data:
        with open(path, "w") as f:
            json.dump(data, f, indent=2)
    else:
        os.remove(path)
    print("[claude-litellm] Cleaned legacy settings file " + path)
PY

# 4c. Same credentials for other Anthropic-SDK tools in the terminal.
python3 - "$CONFIG_FILE" "$HOME/.config/anthropic.env" <<'PY'
import json, os, shlex, sys
env = json.load(open(sys.argv[1]))["settings_env"]
path = sys.argv[2]
with open(path, "w") as f:
    for k, v in env.items():
        f.write("export %s=%s\n" % (k, shlex.quote(v)))
os.chmod(path, 0o600)
PY

grep -q 'anthropic.env' "$HOME/.bashrc" 2>/dev/null \
  || echo '[ -f ~/.config/anthropic.env ] && . ~/.config/anthropic.env' >> "$HOME/.bashrc"

log "Claude Code configured for LiteLLM (restart Claude Code / run /mcp to pick up MCP changes)."
) || echo "[claude-litellm] Claude Code setup failed, continuing..."
export PATH="$HOME/.local/bin:$PATH"
# ── end claude-litellm ───────────────────────────────────────────────────────
