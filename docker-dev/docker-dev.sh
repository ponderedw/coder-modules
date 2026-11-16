# ── docker-dev (shared Coder module) ──────────────────────────────────────────
# Installs Docker Engine (CE) on Ubuntu/Debian. Idempotent — skips the apt
# steps if docker-ce is already installed, and skips usermod if the user is
# already in the docker group.
(
set -uo pipefail

log() { echo "[docker-dev] $*"; }

CONFIG_B64='${config_b64}'

if ! command -v python3 >/dev/null 2>&1; then
  log "python3 not found; cannot run docker-dev setup."
  exit 1
fi

CONFIG_FILE="$(mktemp)"
trap 'rm -f "$CONFIG_FILE"' EXIT
echo "$CONFIG_B64" | base64 -d > "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

cfg() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))[sys.argv[2]]; print(v if isinstance(v,str) else json.dumps(v))' "$CONFIG_FILE" "$1"; }

_user="$(cfg docker_user)"
_start="$(cfg start_service)"

# ── 1. Install Docker Engine ──────────────────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker Engine..."
  sudo apt-get install -y ca-certificates curl gnupg
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  sudo mkdir -p /etc/apt/sources.list.d
  VERSION_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io
  log "Docker Engine installed."
else
  log "Docker already installed, skipping."
fi

# ── 2. Add user to docker group ───────────────────────────────────────────────
if ! groups "$_user" 2>/dev/null | grep -q '\bdocker\b'; then
  sudo usermod -aG docker "$_user"
  log "Added $_user to docker group."
else
  log "$_user already in docker group, skipping."
fi

# ── 3. Start daemon ───────────────────────────────────────────────────────────
if [ "$_start" = "true" ]; then
  sudo service docker start || log "docker start failed (may already be running)"
fi

) || echo "[docker-dev] setup failed, continuing..."
# ── end docker-dev ────────────────────────────────────────────────────────────
