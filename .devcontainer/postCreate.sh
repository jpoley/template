#!/usr/bin/env bash
# Runs once when the devcontainer is built. Delegates to install/ so there's
# one source of truth for environment setup.
set -euo pipefail

cd "$(dirname "$0")/.."

bash install/bootstrap.sh
