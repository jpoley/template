#!/usr/bin/env bash
# Runs once when the devcontainer is built. Delegates to install/ so there's
# one source of truth for environment setup.
set -euo pipefail

cd "$(dirname "$0")/.."

bash install/bootstrap.sh

# gh copilot extension, if gh is authed (non-fatal)
if command -v gh >/dev/null 2>&1; then
  gh extension install github/gh-copilot || true
fi
