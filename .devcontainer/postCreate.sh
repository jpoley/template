#!/usr/bin/env bash
# Runs once when the devcontainer is built. Delegates to install/ so there's
# one source of truth for environment setup.
set -euo pipefail

cd "$(dirname "$0")/.."

# Persist tool paths for non-VS-Code shells (devcontainer.json sets the same
# via containerEnv for VS Code terminals and extensions).
RC="$HOME/.bashrc"
MARKER='# >>> devcontainer tool paths >>>'
if ! grep -qF "$MARKER" "$RC" 2>/dev/null; then
  cat >>"$RC" <<'EOF'

# >>> devcontainer tool paths >>>
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$HOME/.dotnet:$HOME/.local/bin:$HOME/.bun/bin:$PATH"
# <<< devcontainer tool paths <<<
EOF
fi

export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$HOME/.dotnet:$HOME/.local/bin:$HOME/.bun/bin:$PATH"

bash install/bootstrap.sh
