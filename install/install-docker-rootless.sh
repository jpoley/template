#!/usr/bin/env bash
# Install rootless Docker — no Docker Desktop, no daemon-running-as-root.
#
# Rootless Docker still needs a few host packages (uidmap, slirp4netns,
# fuse-overlayfs, iptables, dbus-user-session). These come from your distro
# and require sudo to install *once*. If sudo isn't available, this script
# prints the exact commands the admin needs to run.
#
# After the one-time apt step, everything runs as your user. No groups,
# no socket permissions, no Desktop.
#
# Docs: https://docs.docker.com/engine/security/rootless/

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/_common.sh"

install_prereqs() {
  local pkgs=(uidmap dbus-user-session slirp4netns fuse-overlayfs iptables)
  local missing=()
  for p in "${pkgs[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    log "rootless prereqs already installed"
    return 0
  fi

  if sudo -n true 2>/dev/null; then
    log "installing prereqs via sudo: ${missing[*]}"
    sudo apt-get update -qq
    sudo apt-get install -y "${missing[@]}"
    return 0
  fi

  cat >&2 <<EOF
[install] Rootless docker needs these packages installed once via sudo:

  sudo apt-get update && sudo apt-get install -y ${missing[*]}

Run that command, then re-run this script.
EOF
  return 1
}

install_docker_binaries() {
  if have dockerd-rootless.sh && have docker; then
    log "docker rootless binaries already present"
    return 0
  fi
  log "fetching docker rootless installer"
  curl -fsSL https://get.docker.com/rootless | sh
}

setup_rootless() {
  # Populate subuid/subgid if missing (on WSL2 these often are missing).
  if ! grep -q "^$(id -un):" /etc/subuid 2>/dev/null || ! grep -q "^$(id -un):" /etc/subgid 2>/dev/null; then
    log "adding $(id -un) to /etc/subuid and /etc/subgid (needs sudo)"
    if sudo -n true 2>/dev/null; then
      printf '%s:100000:65536\n' "$(id -un)" | sudo tee -a /etc/subuid >/dev/null
      printf '%s:100000:65536\n' "$(id -un)" | sudo tee -a /etc/subgid >/dev/null
    else
      log "cannot update /etc/subuid without sudo — ask your admin"
      return 1
    fi
  fi

  if [ ! -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/docker.sock" ]; then
    log "starting dockerd-rootless"
    "$HOME/bin/dockerd-rootless-setuptool.sh" install --skip-iptables || true
    systemctl --user enable docker || true
    systemctl --user start docker || true
  fi
}

print_env_hint() {
  cat <<EOF

Add to ~/.bashrc / ~/.zshrc:
  export PATH=\$HOME/bin:\$PATH
  export DOCKER_HOST=unix://\$XDG_RUNTIME_DIR/docker.sock

Then verify:
  docker run --rm hello-world

EOF
}

install_prereqs
install_docker_binaries
setup_rootless
print_env_hint
