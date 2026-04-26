# shellcheck shell=bash
# Shared helpers for install/*.sh scripts.

log() { printf '[install] %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
ensure_dir() { mkdir -p "$1"; }

# Enterprise CA toggle. The single source of truth is the file
# certs/enterprise-ca.crt — when present and non-empty, every install/*.sh
# script picks up the standard CA_BUNDLE / NODE_EXTRA_CA_CERTS / SSL_CERT_FILE /
# GIT_SSL_CAINFO env vars so `curl`, `npm`, `bun install`, `dotnet-install.sh`,
# and friends all trust the enterprise root.
#
# scripts/enterprise-cert.sh writes a richer enterprise-ca.env alongside the
# cert; when present we source it (covers AWS_CA_BUNDLE, REQUESTS_CA_BUNDLE,
# etc.). When the user drops the cert in by hand without running the script,
# we fall back to exporting the common subset directly so the toggle still
# works.
__SCRIPT_DIR_FOR_CA="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
__ENTERPRISE_CA_ROOT="$(cd "$__SCRIPT_DIR_FOR_CA/.." && pwd)/certs"
__ENTERPRISE_CA_CERT="$__ENTERPRISE_CA_ROOT/enterprise-ca.crt"
__ENTERPRISE_CA_ENV="$__ENTERPRISE_CA_ROOT/enterprise-ca.env"
if [ -s "$__ENTERPRISE_CA_CERT" ]; then
  if [ -f "$__ENTERPRISE_CA_ENV" ]; then
    # shellcheck disable=SC1090
    . "$__ENTERPRISE_CA_ENV"
  else
    export ENTERPRISE_CA_BUNDLE="$__ENTERPRISE_CA_CERT"
    export NODE_EXTRA_CA_CERTS="$__ENTERPRISE_CA_CERT"
    export SSL_CERT_FILE="$__ENTERPRISE_CA_CERT"
    export CURL_CA_BUNDLE="$__ENTERPRISE_CA_CERT"
    export GIT_SSL_CAINFO="$__ENTERPRISE_CA_CERT"
    log "enterprise-ca.env missing; exported common CA env vars directly. Run scripts/enterprise-cert.sh enable for the full set."
  fi
  log "enterprise CA toggle ON — using $__ENTERPRISE_CA_CERT"
fi
unset __SCRIPT_DIR_FOR_CA __ENTERPRISE_CA_ROOT __ENTERPRISE_CA_CERT __ENTERPRISE_CA_ENV

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
