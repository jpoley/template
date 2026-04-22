#!/usr/bin/env bash
# Bootstrap all host-side tooling this template needs.
# Idempotent: re-running is safe.
#
# Installs (userspace, no sudo required except where noted):
#   - bun       (via npm)
#   - .NET 10 SDK (via dotnet-install.sh)
#   - terraform (pinned binary)
#   - backlog.md CLI (via npm)
#   - gh CLI hint (requires sudo; skipped if not present, user prompted)
#   - Docker hint  (requires sudo / Docker Desktop; skipped)
#
# Usage:
#   ./install/bootstrap.sh
#
# After running, add the following to your shell rc if not already present:
#   export PATH="$HOME/.dotnet:$HOME/.local/bin:$HOME/.bun/bin:$PATH"
#   export DOTNET_ROOT="$HOME/.dotnet"

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/_common.sh"

log "bootstrap: starting"

bash "$SCRIPT_DIR/install-node.sh"
bash "$SCRIPT_DIR/install-bun.sh"
bash "$SCRIPT_DIR/install-dotnet.sh"
bash "$SCRIPT_DIR/install-terraform.sh"
bash "$SCRIPT_DIR/install-cli-tools.sh"

# Host-only: the devcontainer CLI. No-op inside a container.
bash "$SCRIPT_DIR/install-devcontainer-cli.sh"

# Docker is non-fatal: we need it at `docker compose up` time but not to build.
bash "$SCRIPT_DIR/install-docker.sh" || log "docker not available — skipping (compose will fail until fixed)"

bash "$SCRIPT_DIR/install-deps.sh"

# Playwright is non-fatal: skip if the headless deps can't be wired.
bash "$SCRIPT_DIR/install-playwright.sh" || log "playwright not available — skipping (e2e will fail until fixed)"

log "bootstrap: done"
log ""
log "Add this to your ~/.bashrc / ~/.zshrc if not already present:"
log '  export PATH="$HOME/.dotnet:$HOME/.local/bin:$HOME/.bun/bin:$PATH"'
log '  export DOTNET_ROOT="$HOME/.dotnet"'
log ""
log "Verify:"
log "  bun --version && dotnet --version && terraform version && backlog --version"
