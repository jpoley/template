#!/usr/bin/env bash
# Upgrade the CLI tools this template installs. Safe to run on host or inside
# the devcontainer — each tool is checked for presence first.
#
# Usage:
#   ./install/upgrade.sh           # upgrade everything present
#   ./install/upgrade.sh claude    # upgrade only named tool(s)
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/_common.sh"

targets=("$@")
want() {
  [ "${#targets[@]}" -eq 0 ] && return 0
  for t in "${targets[@]}"; do [ "$t" = "$1" ] && return 0; done
  return 1
}

if want claude && have claude; then
  log "upgrading Claude Code CLI"
  claude update || log "claude update failed (non-fatal)"
fi

if want copilot && have npm; then
  log "upgrading GitHub Copilot CLI (@github/copilot)"
  npm install -g @github/copilot@latest || log "@github/copilot upgrade failed (non-fatal)"
fi

if want backlog && have npm; then
  log "upgrading backlog.md"
  npm install -g backlog.md@latest || log "backlog.md upgrade failed (non-fatal)"
fi

# devcontainer CLI is host-only.
if want devcontainer && have npm && ! in_container; then
  log "upgrading @devcontainers/cli"
  npm install -g @devcontainers/cli@latest || log "@devcontainers/cli upgrade failed (non-fatal)"
fi

log "upgrade: done"
