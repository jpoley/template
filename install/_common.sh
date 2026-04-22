# shellcheck shell=bash
# Shared helpers for install/*.sh scripts.

log() { printf '[install] %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
ensure_dir() { mkdir -p "$1"; }

ensure_local_bin_on_path() {
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) : ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
  esac
}
