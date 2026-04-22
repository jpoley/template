#!/usr/bin/env bash
# Install .NET 10 SDK into ~/.dotnet (userspace, no sudo).
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/_common.sh"

TARGET="$HOME/.dotnet"
CHANNEL="${DOTNET_CHANNEL:-10.0}"

if have dotnet && dotnet --list-sdks 2>/dev/null | grep -q "^${CHANNEL%.*}\."; then
  log "dotnet ${CHANNEL} already present: $(dotnet --version)"
  exit 0
fi

ensure_dir "$TARGET"
tmp="$(mktemp)"
curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$tmp"
bash "$tmp" --channel "$CHANNEL" --install-dir "$TARGET"
rm -f "$tmp"

# Persist PATH + DOTNET_ROOT
if ! grep -q 'DOTNET_ROOT' "$HOME/.bashrc" 2>/dev/null; then
  {
    echo 'export DOTNET_ROOT="$HOME/.dotnet"'
    echo 'export PATH="$HOME/.dotnet:$PATH"'
  } >>"$HOME/.bashrc"
fi

export DOTNET_ROOT="$TARGET"
export PATH="$TARGET:$PATH"
log "dotnet $(dotnet --version) installed at $TARGET"
