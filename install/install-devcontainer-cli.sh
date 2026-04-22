#!/usr/bin/env bash
# Install the `devcontainer` CLI (@devcontainers/cli) on the host.
# Skipped inside a container — the CLI is only useful on the machine that
# drives `devcontainer up / build / exec`.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/_common.sh"

if in_container; then
  log "inside a container — skipping devcontainer CLI (host-only tool)"
  exit 0
fi

if have devcontainer; then
  log "devcontainer CLI already present: $(devcontainer --version)"
  exit 0
fi

if ! have npm; then
  log "npm not available — install Node first (install-node.sh) then retry"
  exit 1
fi

log "installing @devcontainers/cli"
npm install -g @devcontainers/cli
log "devcontainer $(devcontainer --version) installed"
