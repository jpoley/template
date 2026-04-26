#!/usr/bin/env bash
# Umbrella test runner for the whole template.
#
# Runs every per-component suite, then the closed-loop smoke test. This is
# what contributors and CI invoke before claiming a PR is done — the rule
# from CLAUDE.md is that typecheck + unit tests are necessary but NOT
# sufficient. The smoke step at the end is the deterministic guard.
#
# Usage:
#   scripts/test-all.sh                   # full suite, short-circuit on first failure
#   scripts/test-all.sh --keep-going      # run every component, report at end
#   scripts/test-all.sh --no-smoke        # skip docker compose loop (fast feedback only)
#   scripts/test-all.sh --with-ci         # also run GitHub Actions workflows locally via act
#   scripts/test-all.sh --only backend    # run a single component (backend|frontend|admin|infra|e2e|smoke|ci)
#
# Exits non-zero if any component fails.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Auto-pick up the enterprise CA bundle if the toggle is on. See
# docs/enterprise-proxy.md. The cert file is the actual switch; the env file
# is the richer set written by scripts/enterprise-cert.sh enable.
if [ -s "$REPO_ROOT/certs/enterprise-ca.crt" ]; then
  if [ -f "$REPO_ROOT/certs/enterprise-ca.env" ]; then
    # shellcheck disable=SC1091
    . "$REPO_ROOT/certs/enterprise-ca.env"
  else
    export NODE_EXTRA_CA_CERTS="$REPO_ROOT/certs/enterprise-ca.crt"
    export SSL_CERT_FILE="$REPO_ROOT/certs/enterprise-ca.crt"
    export CURL_CA_BUNDLE="$REPO_ROOT/certs/enterprise-ca.crt"
    echo "test-all: certs/enterprise-ca.env missing; exported common CA env vars directly." >&2
  fi
fi

KEEP_GOING=0
RUN_SMOKE=1
RUN_CI=0
ONLY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --keep-going) KEEP_GOING=1 ;;
    --no-smoke)   RUN_SMOKE=0 ;;
    --with-ci)    RUN_CI=1 ;;
    --only)       ONLY="$2"; shift ;;
    -h|--help)    sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "test-all: unknown arg '$1'" >&2; exit 2 ;;
  esac
  shift
done

# ---------- helpers ----------
declare -a RESULTS=()
FAILED=0

banner() { printf '\n\e[1;36m━━━ %s ━━━\e[0m\n' "$*"; }
pass()   { printf '\e[1;32m  PASS\e[0m  %s\n' "$*"; RESULTS+=("PASS  $*"); }
miss()   { printf '\e[1;31m  FAIL\e[0m  %s\n' "$*"; RESULTS+=("FAIL  $*"); FAILED=1; }
skip()   { printf '\e[1;33m  SKIP\e[0m  %s\n' "$*"; RESULTS+=("SKIP  $*"); }

want() {
  # $1 = component name. Returns 0 if it should run (matches --only or no --only).
  [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]
}

run_step() {
  local name="$1"; shift
  banner "$name"
  if "$@"; then
    pass "$name"
    return 0
  fi
  miss "$name"
  if [ "$KEEP_GOING" -eq 0 ]; then
    summary
    exit 1
  fi
  return 1
}

summary() {
  banner "Summary"
  printf '%s\n' "${RESULTS[@]}"
  if [ "$FAILED" -ne 0 ]; then
    printf '\n\e[1;31mOne or more components failed.\e[0m\n'
  else
    printf '\n\e[1;32mAll green.\e[0m\n'
  fi
}

# ---------- component steps ----------
step_backend() {
  ( cd backend && dotnet test Backend.sln -c Release --nologo )
}

step_frontend() {
  ( cd frontend && bun run typecheck && bun run lint && bun run test && bun run build )
}

step_admin() {
  ( cd admin && bun run typecheck && bun run lint && bun run test && bun run build )
}

step_infra() {
  ( cd infra && terraform fmt -check -recursive && terraform init -backend=false -input=false >/dev/null && terraform validate ) || return 1
  # tflint runs in CI; run it locally too if the binary is installed. Skip
  # silently otherwise so first-time contributors aren't blocked.
  if command -v tflint >/dev/null 2>&1; then
    ( cd infra && tflint --init >/dev/null && tflint --recursive --minimum-failure-severity=error )
  else
    echo "    (skip: tflint not installed — CI will still run it)"
  fi
}

step_e2e() {
  # Playwright runs against the smoke-stack-up compose; skip here unless
  # explicitly requested, since smoke.sh already covers the runtime surface.
  ( cd e2e && bun run test )
}

step_smoke() {
  scripts/smoke.sh
}

step_ci() {
  scripts/ci.sh
}

# ---------- run ----------
if want backend;  then run_step "backend (dotnet test)"                            step_backend  || true; fi
if want frontend; then run_step "frontend (typecheck + lint + vitest + build)"     step_frontend || true; fi
if want admin;    then run_step "admin (typecheck + lint + vitest + build)"        step_admin    || true; fi
if want infra;    then run_step "infra (terraform fmt + validate + tflint)"        step_infra    || true; fi

if [ -n "$ONLY" ] && [ "$ONLY" = "e2e" ]; then
  run_step "e2e (playwright)" step_e2e || true
fi

if [ "$RUN_SMOKE" -eq 1 ] && want smoke; then
  run_step "smoke (closed-loop docker compose)" step_smoke || true
elif want smoke; then
  skip "smoke (--no-smoke)"
fi

# ci (act) is opt-in: slow, pulls multi-GB runner images. Runs iff --with-ci
# or --only ci.
if [ -n "$ONLY" ] && [ "$ONLY" = "ci" ]; then
  run_step "ci (act — local GitHub Actions)" step_ci || true
elif [ -z "$ONLY" ] && [ "$RUN_CI" -eq 1 ]; then
  run_step "ci (act — local GitHub Actions)" step_ci || true
fi

summary
exit "$FAILED"
