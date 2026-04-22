#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/_common.sh"

if have bun; then
  log "bun already present: $(bun --version)"
  exit 0
fi

# Official installer requires unzip. Fall back to npm (no system deps).
if have unzip; then
  log "installing bun via official installer"
  curl -fsSL https://bun.sh/install | bash
  echo 'export PATH="$HOME/.bun/bin:$PATH"' >>"$HOME/.bashrc"
else
  log "unzip not present; installing bun via npm"
  if ! have npm; then
    log "ERROR: neither unzip nor npm present; install one first"
    exit 1
  fi
  npm install -g bun
fi
log "bun $(bun --version) installed"
