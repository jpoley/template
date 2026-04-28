#!/usr/bin/env bash
# scripts/build-bases.sh — build the three local base images consumed by the
# app Dockerfiles (backend / frontend / admin).
#
# Bases hold the slow stuff (SDK + restored deps + enterprise CA). They are
# optional: every Dockerfile defaults BASE_IMAGE to the upstream SDK/bun
# image, so a build without these bases still works — just slower.
#
# WE NEVER REBUILD ON A SCHEDULE. A base is rebuilt only when one of its
# inputs has changed:
#   backend:  Dockerfile.base, global.json, Directory.Build.props,
#             src/**/*.csproj, tests/**/*.csproj, certs/enterprise-ca.crt
#   frontend: Dockerfile.base, package.json, bun.lock(b), certs/enterprise-ca.crt
#   admin:    Dockerfile.base, package.json, bun.lock(b), certs/enterprise-ca.crt
#
# Usage:
#   scripts/build-bases.sh                # build only what's stale
#   scripts/build-bases.sh --force        # rebuild all three regardless
#   scripts/build-bases.sh --only backend # one service only
#   scripts/build-bases.sh --check        # report which bases are stale, exit 1 if any are
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

FORCE=0
ONLY=""
CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1 ;;
    --only)  ONLY="$2"; shift ;;
    --check) CHECK=1 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

# A base is stale if any input file is newer than the image's creation time.
# `docker image inspect` returns RFC3339; convert to epoch for comparison.
image_created_epoch() {
  local img="$1" t
  t=$(docker image inspect -f '{{.Created}}' "$img" 2>/dev/null || true)
  if [ -z "$t" ]; then echo 0; return; fi
  if date --version >/dev/null 2>&1; then
    date -d "$t" +%s
  else
    # macOS / BSD date
    python3 -c "import sys, datetime; print(int(datetime.datetime.fromisoformat(sys.argv[1].replace('Z','+00:00')).timestamp()))" "$t"
  fi
}

newest_input_epoch() {
  # newest_input_epoch <path...> — picks the max mtime, 0 if none exist
  local m=0 f t
  for f in "$@"; do
    [ -e "$f" ] || continue
    if [ -d "$f" ]; then
      while IFS= read -r child; do
        t=$(stat -f %m "$child" 2>/dev/null || stat -c %Y "$child" 2>/dev/null || echo 0)
        [ "$t" -gt "$m" ] && m=$t
      done < <(find "$f" -type f)
    else
      t=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
      [ "$t" -gt "$m" ] && m=$t
    fi
  done
  echo "$m"
}

inputs_for() {
  case "$1" in
    backend)
      printf '%s\n' \
        backend/Dockerfile.base \
        backend/global.json \
        backend/Directory.Build.props \
        backend/Backend.sln
      find backend/src backend/tests -name '*.csproj' 2>/dev/null
      [ -s certs/enterprise-ca.crt ] && echo certs/enterprise-ca.crt
      ;;
    frontend|admin)
      printf '%s\n' \
        "$1/Dockerfile.base" \
        "$1/package.json"
      [ -e "$1/bun.lock" ]  && echo "$1/bun.lock"
      [ -e "$1/bun.lockb" ] && echo "$1/bun.lockb"
      [ -s certs/enterprise-ca.crt ] && echo certs/enterprise-ca.crt
      ;;
  esac
}

is_stale() {
  local svc="$1" tag
  tag="projecttemplate/${svc}-base:local"
  local img_epoch newest_epoch
  img_epoch=$(image_created_epoch "$tag")
  if [ "$img_epoch" -eq 0 ]; then return 0; fi
  # shellcheck disable=SC2046
  newest_epoch=$(newest_input_epoch $(inputs_for "$svc"))
  [ "$newest_epoch" -gt "$img_epoch" ]
}

build_one() {
  local svc="$1" tag="projecttemplate/${svc}-base:local"
  echo "==> Building $tag"
  docker build \
    --file "${svc}/Dockerfile.base" \
    --tag  "$tag" \
    --build-context enterprise-ca=./certs \
    "${svc}"
}

services=(backend frontend admin)
[ -n "$ONLY" ] && services=("$ONLY")

stale=()
for svc in "${services[@]}"; do
  if [ "$FORCE" -eq 1 ] || is_stale "$svc"; then
    stale+=("$svc")
  else
    echo "✓ $svc base up to date — skipping"
  fi
done

if [ "$CHECK" -eq 1 ]; then
  if [ ${#stale[@]} -eq 0 ]; then
    echo "All bases up to date."
    exit 0
  fi
  echo "Stale bases: ${stale[*]}" >&2
  exit 1
fi

if [ ${#stale[@]} -eq 0 ]; then
  echo "Nothing to do."
  exit 0
fi

# docker buildx is required for --build-context (named contexts).
if ! docker buildx version >/dev/null 2>&1; then
  echo "ERROR: docker buildx not available. Install docker buildx (ships with Docker Desktop)." >&2
  exit 1
fi

for svc in "${stale[@]}"; do
  build_one "$svc"
done

echo
echo "Built bases: ${stale[*]}"
echo "Pass them to docker / compose with: --build-arg BASE_IMAGE=projecttemplate/<svc>-base:local"
