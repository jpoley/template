#!/usr/bin/env bash
# Install per-project dependencies: bun install in frontend+internal, dotnet restore,
# and terraform init -backend=false. Safe to re-run.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/_common.sh"

export PATH="$HOME/.dotnet:$HOME/.local/bin:$HOME/.bun/bin:$PATH"
export DOTNET_ROOT="$HOME/.dotnet"

log "deps: frontend"
( cd "$ROOT/frontend" && bun install )

log "deps: internal"
( cd "$ROOT/internal" && bun install )

log "deps: backend"
( cd "$ROOT/backend" && dotnet restore Backend.sln )

if have terraform; then
  log "deps: terraform init (no backend)"
  ( cd "$ROOT/infra" && terraform init -backend=false -upgrade )
fi

log "deps: done"
