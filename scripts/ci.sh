#!/usr/bin/env bash
# Run the repo's GitHub Actions workflows locally via `act`.
#
# Usage:
#   scripts/ci.sh                          # run the safe default subset (excludes build-images)
#   scripts/ci.sh --event pull_request     # use a different event (default: push)
#   scripts/ci.sh --list                   # list what act would run, don't execute
#   scripts/ci.sh --all                    # include build-images.yml (needs registry secrets)
#   ACT_WORKFLOWS='frontend.yml,admin.yml' scripts/ci.sh
#   scripts/ci.sh -- -j backend-test       # pass args after -- straight through to act
#
# Why this exists:
# - Typecheck + unit tests + smoke.sh verify the code. `act` verifies the
#   pipeline that runs the code — caught by it: YAML syntax, action version
#   drift, matrix typos, cache key collisions, runner-image assumptions.
# - `build-images.yml` is excluded by default because it needs registry
#   secrets (ACR/GHCR). Opt in with --all and provide secrets via .secrets.
#
# Requires: act (https://github.com/nektos/act), docker.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

EVENT="push"
LIST_ONLY=0
INCLUDE_ALL=0
PASSTHROUGH=()

while [ $# -gt 0 ]; do
  case "$1" in
    --event) EVENT="$2"; shift ;;
    --list)  LIST_ONLY=1 ;;
    --all)   INCLUDE_ALL=1 ;;
    --)      shift; PASSTHROUGH=("$@"); break ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "ci: unknown arg '$1' (pass act flags after --)" >&2; exit 2 ;;
  esac
  shift
done

command -v act >/dev/null 2>&1 || {
  cat >&2 <<'EOF'
ci: `act` is not installed.
  macOS:   brew install act
  Linux:   curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
  More:    https://github.com/nektos/act
EOF
  exit 127
}
command -v docker >/dev/null 2>&1 || { echo "ci: docker is required by act" >&2; exit 127; }

# act < 0.2.87 rejects actions using node24 runtime, which every pinned
# actions/* v5+/v6+ action in this repo uses. Fail fast with a clear hint.
ACT_VERSION="$(act --version 2>/dev/null | awk '{print $NF}')"
min_version="0.2.87"
if [ -n "$ACT_VERSION" ] && [ "$(printf '%s\n%s\n' "$min_version" "$ACT_VERSION" | sort -V | head -1)" != "$min_version" ]; then
  cat >&2 <<EOF
ci: act $ACT_VERSION is too old (need >= $min_version for node24 runtime).
    Upgrade:  brew upgrade act   (or reinstall via the script above)
EOF
  exit 127
fi

# -----------------------------------------------------------------------------
# Workflow selection
# -----------------------------------------------------------------------------
# Default subset: everything that runs on `push` without registry secrets.
# Override with ACT_WORKFLOWS='a.yml,b.yml' or --all.
DEFAULT_SAFE=(backend.yml frontend.yml admin.yml e2e.yml infra.yml)
UNSAFE=(build-images.yml)

if [ -n "${ACT_WORKFLOWS:-}" ]; then
  IFS=',' read -r -a SELECTED <<<"$ACT_WORKFLOWS"
elif [ "$INCLUDE_ALL" -eq 1 ]; then
  SELECTED=("${DEFAULT_SAFE[@]}" "${UNSAFE[@]}")
else
  SELECTED=("${DEFAULT_SAFE[@]}")
fi

# -----------------------------------------------------------------------------
# act invocation
# -----------------------------------------------------------------------------
# Pin a Linux runner image that matches the real github-hosted runner closely.
# `catthehacker/ubuntu:act-latest` (act's "medium" default) omits node from
# PATH in post-step execs, which breaks every JS-based `uses:` action's
# cleanup (setup-bun, upload-artifact, etc — see nektos/act#107). The `full`
# image ships node + the full toolcache and is the known-good choice.
# Override via ACT_IMAGE env if you want the smaller image.
ACT_IMAGE="${ACT_IMAGE:-ghcr.io/catthehacker/ubuntu:full-latest}"

# Local artifact server so actions/upload-artifact doesn't fail with
# "Unable to get the ACTIONS_RUNTIME_TOKEN" — that env var only exists on
# real GitHub runners. Artifacts land under this dir and persist across runs.
ACT_ARTIFACTS="${ACT_ARTIFACTS:-/tmp/act-artifacts}"
mkdir -p "$ACT_ARTIFACTS"

ACT_BASE=(
  act "$EVENT"
  --pull=false
  -P "ubuntu-latest=$ACT_IMAGE"
  --artifact-server-path "$ACT_ARTIFACTS"
)

# Apple Silicon: force linux/amd64 so actions that ship x86_64 binaries work.
# Harmless on Intel/Linux.
if [ "$(uname -m)" = "arm64" ] || [ "$(uname -m)" = "aarch64" ]; then
  ACT_BASE+=(--container-architecture linux/amd64)

  # Docker on Apple Silicon defaults to arm64 even when --platform is passed,
  # so the cached image may be the wrong arch. If so, pull the amd64 variant
  # by digest and retag. Costly once, free afterwards.
  if docker image inspect "$ACT_IMAGE" >/dev/null 2>&1; then
    actual_arch=$(docker inspect --format '{{.Architecture}}' "$ACT_IMAGE" 2>/dev/null || echo "")
    if [ "$actual_arch" != "amd64" ] && [ -n "$actual_arch" ]; then
      echo "==> Cached $ACT_IMAGE is $actual_arch; pulling amd64 variant (one-time)"
      amd64_digest=$(docker manifest inspect "$ACT_IMAGE" 2>/dev/null \
        | awk '/"architecture": "amd64"/{p=1} p && /"digest"/{print; exit}' \
        | sed -E 's/.*"digest": "([^"]+)".*/\1/')
      if [ -n "$amd64_digest" ]; then
        img_no_tag="${ACT_IMAGE%:*}"
        docker rmi "$ACT_IMAGE" >/dev/null 2>&1 || true
        docker pull "${img_no_tag}@${amd64_digest}" >/dev/null
        docker tag "${img_no_tag}@${amd64_digest}" "$ACT_IMAGE"
      fi
    fi
  fi
fi

# Surface .secrets if it exists (gitignored). Users can create one with
# GITHUB_TOKEN / registry creds for --all runs.
if [ -f .secrets ]; then
  ACT_BASE+=(--secret-file .secrets)
fi

failed=()
for wf in "${SELECTED[@]}"; do
  path=".github/workflows/$wf"
  if [ ! -f "$path" ]; then
    echo "ci: skip $wf (not found)" >&2
    continue
  fi

  args=("${ACT_BASE[@]}" -W "$path")
  if [ "$LIST_ONLY" -eq 1 ]; then
    args+=(--list)
  fi
  args+=(${PASSTHROUGH[@]+"${PASSTHROUGH[@]}"})

  printf '\n\e[1;34m==> act %s (%s)\e[0m\n' "$EVENT" "$wf"
  if "${args[@]}"; then
    printf '\e[1;32m    ✓ %s\e[0m\n' "$wf"
  else
    printf '\e[1;31m    ✗ %s\e[0m\n' "$wf"
    failed+=("$wf")
  fi
done

if [ "${#failed[@]}" -gt 0 ]; then
  printf '\n\e[1;31mci: failed workflows:\e[0m %s\n' "${failed[*]}" >&2
  exit 1
fi
printf '\n\e[1;32mci: all workflows passed\e[0m\n'
