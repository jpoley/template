#!/usr/bin/env bash
# Ensure a working `docker` command. Tries several paths based on host.
#
#   - Already works? return
#   - WSL with Docker Desktop: detect and guide
#   - Native Linux with sudo: install docker-ce
#   - Native Linux without sudo: delegate to install-docker-rootless.sh
#
# Safe to re-run.

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/_common.sh"

if docker version >/dev/null 2>&1; then
  log "docker already working: $(docker version --format '{{.Client.Version}}')"
  exit 0
fi

is_wsl=0
grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null && is_wsl=1

if [ "$is_wsl" = "1" ]; then
  if [ -L /usr/bin/docker ] && [ ! -e /usr/bin/docker ]; then
    cat >&2 <<'EOF'
[install] Docker Desktop is installed on Windows but WSL integration is not active.
[install]
[install] Two options:
[install]   (1) Start Docker Desktop on Windows → Settings → Resources → WSL integration
[install]       → enable this distro → restart this shell.
[install]   (2) Skip Desktop entirely — install rootless docker:
[install]       ./install/install-docker-rootless.sh
EOF
    exit 1
  fi
  log "Docker client not present. Options:"
  log "  - Start Docker Desktop and enable WSL integration (recommended): https://docs.docker.com/desktop/wsl/"
  log "  - Or run: ./install/install-docker-rootless.sh"
  exit 1
fi

# Native Linux
if have sudo && sudo -n true 2>/dev/null; then
  if [ -f /etc/debian_version ]; then
    log "installing docker-ce (apt, sudo required)"
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
    distro_id="$(. /etc/os-release && echo "$ID")"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${distro_id} ${codename} stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo usermod -aG docker "$USER"
    log "docker installed. Log out + back in for the docker group to take effect."
    exit 0
  fi
  log "Unsupported distro for automatic docker install."
  log "See https://docs.docker.com/engine/install/"
  exit 1
fi

log "docker not installed and passwordless sudo unavailable."
log "Try rootless: ./install/install-docker-rootless.sh"
exit 1
