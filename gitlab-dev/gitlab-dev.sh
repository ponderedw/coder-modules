# ── gitlab-dev (shared Coder module) ──────────────────────────────────────────
# Rendered by Terraform templatefile() and interpolated into the template's
# startup_script. Runs in a subshell so its exits can't abort the outer script.
(
set -uo pipefail

log() { echo "[gitlab-dev] $*"; }

CONFIG_B64='${config_b64}'

if ! command -v python3 >/dev/null 2>&1; then
  log "python3 not found; cannot run gitlab-dev setup."
  exit 1
fi

CONFIG_FILE="$(mktemp)"
trap 'rm -f "$CONFIG_FILE"' EXIT
echo "$CONFIG_B64" | base64 -d > "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

cfg() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))[sys.argv[2]]; print(v if isinstance(v,str) else json.dumps(v))' "$CONFIG_FILE" "$1"; }

# ── 1. Git config ─────────────────────────────────────────────────────────────
_git_name="$(cfg git_name)"
_git_email="$(cfg git_email)"
[ -n "$_git_name" ]  && git config --global user.name  "$_git_name"
[ -n "$_git_email" ] && git config --global user.email "$_git_email"
git config --global pull.rebase false
git config --global push.default current

# ── 2. Build auth URL ─────────────────────────────────────────────────────────
_repo_url="$(cfg repo_url)"
_token="$(cfg token)"
_target="$(cfg target_dir)"

if [ -n "$_token" ]; then
  _auth_url="$(python3 -c "
import sys
url, tok = sys.argv[1], sys.argv[2]
print(url.replace('https://', 'https://oauth2:' + tok + '@', 1))
" "$_repo_url" "$_token")"
else
  _auth_url="$_repo_url"
fi

# ── 3. Clone / pull ───────────────────────────────────────────────────────────
if [ -d "$_target/.git" ]; then
  log "Repository exists at $_target, pulling..."
  git -C "$_target" remote set-url origin "$_auth_url"
  git -C "$_target" pull || log "Git pull failed, continuing..."
elif [ -d "$_target" ] && [ -n "$(ls -A "$_target" 2>/dev/null)" ]; then
  log "WARNING: $_target exists and is not empty but not a git repo — skipping."
else
  log "Cloning $_repo_url into $_target..."
  if git clone "$_auth_url" "$_target"; then
    log "Clone succeeded."
  else
    log "Clone failed (check the GitLab token parameter). Will retry on next start."
  fi
fi

# ── 4. Hooks script ───────────────────────────────────────────────────────────
_hooks="$(cfg hooks_script)"
if [ -n "$_hooks" ] && [ -d "$_target/.git" ] && [ -f "$_target/$_hooks" ]; then
  log "Running $_hooks..."
  (cd "$_target" && chmod +x "$_hooks" && ./"$_hooks") || log "$_hooks failed, continuing..."
fi

) || echo "[gitlab-dev] setup failed, continuing..."
# ── end gitlab-dev ────────────────────────────────────────────────────────────
