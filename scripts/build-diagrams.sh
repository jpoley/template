#!/usr/bin/env bash
# Renders every docs/diagrams/*.mmd to a same-named PNG using mermaid-cli in a
# throwaway Docker container. No host-side toolchain required — only Docker.
#
# Usage:
#   scripts/build-diagrams.sh           # rebuild all
#   scripts/build-diagrams.sh foo.mmd   # rebuild one
#
# Theme / size tweaks: edit the mmdc args below, or add a per-file front-matter
# block in the .mmd source (mermaid supports `---\nconfig:\n  theme: dark\n---`).
set -euo pipefail

cd "$(dirname "$0")/.."

DIAGRAMS_DIR="docs/diagrams"
IMAGE="minlag/mermaid-cli:11.12.0"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "==> Pulling $IMAGE (first run only)"
  docker pull "$IMAGE"
fi

render_one() {
  local src="$1"
  local out="${src%.mmd}.png"
  echo "  $src -> $out"
  docker run --rm \
    -u "$(id -u):$(id -g)" \
    -v "$PWD/$DIAGRAMS_DIR:/data" \
    "$IMAGE" \
    -i "/data/$(basename "$src")" \
    -o "/data/$(basename "$out")" \
    -b transparent \
    -w 1600 -H 1000 \
    -s 2
}

if [ $# -gt 0 ]; then
  for arg in "$@"; do render_one "$DIAGRAMS_DIR/$(basename "$arg")"; done
else
  shopt -s nullglob
  files=("$DIAGRAMS_DIR"/*.mmd)
  if [ ${#files[@]} -eq 0 ]; then
    echo "No .mmd files in $DIAGRAMS_DIR/"; exit 0
  fi
  echo "==> Rendering ${#files[@]} diagram(s)"
  for f in "${files[@]}"; do render_one "$f"; done
fi

echo "==> Done. Commit the .mmd source and the .png output together."
