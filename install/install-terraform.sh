#!/usr/bin/env bash
# Install a pinned terraform into ~/.local/bin (no sudo).
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/_common.sh"

VERSION="${TERRAFORM_VERSION:-1.9.8}"
BIN_DIR="$HOME/.local/bin"

if have terraform && terraform version | head -1 | grep -q "v${VERSION}"; then
  log "terraform ${VERSION} already present"
  exit 0
fi

ensure_dir "$BIN_DIR"
ensure_local_bin_on_path

arch="$(uname -m)"
case "$arch" in
  x86_64) arch="amd64" ;;
  aarch64|arm64) arch="arm64" ;;
  *) log "unsupported arch: $arch"; exit 1 ;;
esac

tmp="$(mktemp -d)"
url="https://releases.hashicorp.com/terraform/${VERSION}/terraform_${VERSION}_linux_${arch}.zip"
log "downloading $url"
curl -fsSL -o "$tmp/tf.zip" "$url"

# Extract without requiring unzip
python3 -c "import zipfile, sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$tmp/tf.zip" "$tmp"
install -m 0755 "$tmp/terraform" "$BIN_DIR/terraform"
rm -rf "$tmp"
log "terraform $(terraform version | head -1) installed"
