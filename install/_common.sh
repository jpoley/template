# shellcheck shell=bash
# Shared helpers for install/*.sh scripts.

log() { printf '[install] %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
ensure_dir() { mkdir -p "$1"; }

# Source the enterprise CA env file if the toggle is on. This is the single
# place every install/*.sh script picks up CA_BUNDLE / NODE_EXTRA_CA_CERTS /
# SSL_CERT_FILE / GIT_SSL_CAINFO so that `curl`, `npm`, `bun install`,
# `dotnet-install.sh`, and friends all see the enterprise root.
__SCRIPT_DIR_FOR_CA="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
__ENTERPRISE_CA_ENV="$(cd "$__SCRIPT_DIR_FOR_CA/.." && pwd)/certs/enterprise-ca.env"
if [ -f "$__ENTERPRISE_CA_ENV" ]; then
  # shellcheck disable=SC1090
  . "$__ENTERPRISE_CA_ENV"
  log "enterprise CA toggle ON — using $ENTERPRISE_CA_BUNDLE"
fi
unset __SCRIPT_DIR_FOR_CA __ENTERPRISE_CA_ENV

ensure_local_bin_on_path() {
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) : ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
  esac
}

# Returns 0 if we're running inside a container (docker / devcontainer / codespace).
in_container() {
  [ -f /.dockerenv ] || [ "${DEVCONTAINER:-}" = "true" ] || [ -n "${REMOTE_CONTAINERS:-}" ] || [ -n "${CODESPACES:-}" ]
}
