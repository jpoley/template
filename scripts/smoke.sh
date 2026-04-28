#!/usr/bin/env bash
# Closed-loop smoke test: brings up docker compose, exercises every component
# end-to-end, scans logs for errors, tears down.
#
# Usage:
#   scripts/smoke.sh                      # full loop with postgres, rebuild + teardown
#   scripts/smoke.sh --provider sqlserver
#   scripts/smoke.sh --keep-up            # leave stack running on success (for inspection)
#   scripts/smoke.sh --no-build           # skip image rebuild (faster re-runs)
#
# Exits non-zero on any failure. This is the deterministic contract: if this
# passes, the stack works end-to-end. If it fails, the PR is not done —
# typecheck + unit tests alone are insufficient for feature/dependency work.
#
# Requires: docker compose, curl, jq, openssl.
set -euo pipefail

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
    echo "smoke: certs/enterprise-ca.env missing; exported common CA env vars directly." >&2
  fi
fi

PROVIDER="postgres"
KEEP_UP=0
BUILD_ARGS=(--build)
SKIP_BASES=0
BACKEND_URL="http://localhost:6180"
FRONTEND_URL="http://localhost:6173"
ADMIN_URL="http://localhost:6174"
READY_TIMEOUT="${SMOKE_READY_TIMEOUT:-120}"   # per service, seconds
REQUEST_TIMEOUT="${SMOKE_REQUEST_TIMEOUT:-10}"

while [ $# -gt 0 ]; do
  case "$1" in
    --provider) PROVIDER="$2"; shift ;;
    --keep-up)  KEEP_UP=1 ;;
    --no-build) BUILD_ARGS=() ;;
    --skip-bases) SKIP_BASES=1 ;;
    -h|--help)  sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "smoke: unknown arg '$1'" >&2; exit 2 ;;
  esac
  shift
done

case "$PROVIDER" in
  postgres)  DB_PROVIDER="Postgres";  DB_CONTAINER="projecttemplate-postgres" ;;
  sqlserver) DB_PROVIDER="SqlServer"; DB_CONTAINER="projecttemplate-sqlserver" ;;
  *) echo "smoke: --provider must be postgres or sqlserver" >&2; exit 2 ;;
esac

export COMPOSE_PROFILES="$PROVIDER"
export DB_PROVIDER

# Required tool check — fail fast with actionable message if missing.
for tool in docker curl jq openssl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "smoke: '$tool' not found on PATH" >&2; exit 2; }
done

# ---------- helpers ----------
step()  { printf '\n\e[1;34m==> %s\e[0m\n' "$*"; }
ok()    { printf '\e[1;32m    ✓ %s\e[0m\n' "$*"; }
fail()  { printf '\e[1;31m    ✗ %s\e[0m\n' "$*" >&2; exit 1; }

# ---------- .env (POSTGRES_PASSWORD) ----------
# docker compose loads .env automatically from the project dir. Generate the
# secret on first run to mirror rebuild.sh so smoke.sh works on a fresh clone.
if [ ! -f .env ] || ! grep -qE '^POSTGRES_PASSWORD=.+' .env; then
  step "Generating POSTGRES_PASSWORD in .env (first run)"
  touch .env
  pw="$(openssl rand -base64 24 | tr -d '=+/\n' | cut -c1-24)"
  grep -v '^POSTGRES_PASSWORD=' .env > .env.tmp 2>/dev/null || true
  mv .env.tmp .env 2>/dev/null || true
  printf 'POSTGRES_PASSWORD=%s\n' "$pw" >> .env
  chmod 600 .env
fi

# ---------- teardown trap ----------
STACK_UP=0
teardown() {
  local rc=$?
  if [ "$STACK_UP" -eq 1 ]; then
    if [ "$rc" -ne 0 ]; then
      step "Failure — dumping recent logs before teardown"
      docker compose logs --tail=120 --no-color || true
    fi
    if [ "$KEEP_UP" -eq 0 ]; then
      step "Tearing down stack"
      docker compose down -v --remove-orphans >/dev/null 2>&1 || true
    else
      echo "    (stack left running — run 'docker compose down -v' to clean up)"
    fi
  fi
  exit $rc
}
trap teardown EXIT

# ---------- bases ----------
# Build the slow-changing per-service bases first so the app build is a
# cache hit. build-bases.sh is content-addressed: skips per-service when
# nothing relevant changed. Cold first run ~2-3 min; subsequent runs no-op.
# Pass --skip-bases to bypass (forces upstream SDK/bun pulls in the app build).
if [ "$SKIP_BASES" -eq 0 ] && [ ${#BUILD_ARGS[@]} -gt 0 ]; then
  step "Building base images (scripts/build-bases.sh)"
  if scripts/build-bases.sh; then
    docker image inspect projecttemplate/backend-base:local  >/dev/null 2>&1 && export BACKEND_BASE_IMAGE=projecttemplate/backend-base:local
    docker image inspect projecttemplate/frontend-base:local >/dev/null 2>&1 && export FRONTEND_BASE_IMAGE=projecttemplate/frontend-base:local
    docker image inspect projecttemplate/admin-base:local    >/dev/null 2>&1 && export ADMIN_BASE_IMAGE=projecttemplate/admin-base:local
  else
    echo "    base build failed — falling back to upstream BASE_IMAGE" >&2
  fi
fi

# ---------- bring up ----------
step "docker compose up -d ${BUILD_ARGS[*]:-} (profile=$PROVIDER)"
docker compose up -d ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"}
STACK_UP=1

# ---------- wait for readiness ----------
wait_db_healthy() {
  local container="$1" deadline status
  deadline=$(( $(date +%s) + READY_TIMEOUT ))
  while :; do
    status=$(docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null || echo "missing")
    case "$status" in
      healthy) ok "$container healthy"; return 0 ;;
      missing) fail "$container does not exist" ;;
    esac
    [ "$(date +%s)" -lt "$deadline" ] || fail "$container not healthy within ${READY_TIMEOUT}s (last: $status)"
    sleep 2
  done
}

wait_http_ok() {
  local name="$1" url="$2" deadline
  deadline=$(( $(date +%s) + READY_TIMEOUT ))
  while :; do
    if curl -fsS -o /dev/null --max-time 3 "$url" 2>/dev/null; then
      ok "$name reachable at $url"
      return 0
    fi
    [ "$(date +%s)" -lt "$deadline" ] || fail "$name not responding at $url within ${READY_TIMEOUT}s"
    sleep 2
  done
}

step "Waiting for services to become ready"
wait_db_healthy "$DB_CONTAINER"
wait_http_ok backend  "$BACKEND_URL/api/health"
wait_http_ok frontend "$FRONTEND_URL"
wait_http_ok admin    "$ADMIN_URL"

# ---------- backend CRUD round-trip ----------
step "Backend CRUD round-trip (/api/items)"

BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' RETURN 2>/dev/null || true

curl_json() {
  local method="$1" path="$2" expect="$3" body="${4:-}"
  local args=(-sS -o "$BODY_FILE" -w '%{http_code}' --max-time "$REQUEST_TIMEOUT" -X "$method" "$BACKEND_URL$path")
  if [ -n "$body" ]; then
    args+=(-H 'Content-Type: application/json' -d "$body")
  fi
  local code
  code="$(curl "${args[@]}")" || fail "curl $method $path failed (network)"
  if [ "$code" != "$expect" ]; then
    echo "    response body:" >&2
    cat "$BODY_FILE" >&2 || true; echo >&2
    fail "$method $path expected HTTP $expect, got $code"
  fi
}

curl_json GET /api/health 200
ok "GET /api/health → 200"

PK="smoke-$(date +%s)-$$"
curl_json POST /api/items/ 201 "{\"partitionKey\":\"$PK\",\"name\":\"smoke\",\"description\":\"round-trip\"}"
ID="$(jq -r '.id' "$BODY_FILE")"
[ -n "$ID" ] && [ "$ID" != "null" ] || fail "POST /api/items returned no id"
ok "POST /api/items → 201 (id=$ID)"

curl_json GET "/api/items/$PK" 200
jq -e --arg id "$ID" '[.[] | select(.id == $id)] | length == 1' "$BODY_FILE" >/dev/null \
  || fail "GET list did not include created item"
ok "GET /api/items/$PK → 200 (contains created item)"

curl_json GET "/api/items/$PK/$ID" 200
[ "$(jq -r '.name' "$BODY_FILE")" = "smoke" ] || fail "GET single item: name mismatch"
ok "GET /api/items/$PK/$ID → 200 (name=smoke)"

curl_json PUT "/api/items/$PK/$ID" 200 '{"name":"smoke-updated","description":null}'
[ "$(jq -r '.name' "$BODY_FILE")" = "smoke-updated" ] || fail "PUT: name not updated"
ok "PUT /api/items/$PK/$ID → 200 (name=smoke-updated)"

curl_json DELETE "/api/items/$PK/$ID" 204
ok "DELETE /api/items/$PK/$ID → 204"

curl_json GET "/api/items/$PK/$ID" 404
ok "GET /api/items/$PK/$ID after delete → 404"

# ---------- frontend/admin HTML ----------
step "Frontend + admin serve HTML"

check_html() {
  local name="$1" url="$2" body
  body="$(curl -fsS --max-time "$REQUEST_TIMEOUT" "$url")" || fail "$name $url unreachable"
  [ -n "$body" ] || fail "$name $url returned empty body"
  echo "$body" | grep -qi '<!doctype html' || fail "$name $url did not return HTML"
  ok "$name $url → HTML"
}
check_html frontend "$FRONTEND_URL"
check_html admin    "$ADMIN_URL"

# ---------- log scan ----------
step "Scanning container logs for runtime errors"
# Patterns that indicate real runtime breakage (not expected log noise).
# Keep this list tight — false positives erode trust in the smoke test.
BAD_PATTERNS='Unhandled exception|System\.AggregateException|System\.NullReferenceException|StackOverflowException|Npgsql\.PostgresException|Microsoft\.EntityFrameworkCore.*\[10403\]|\[FATAL\]|panic: runtime error|ECONNREFUSED.*(?!:5432)'
if docker compose logs --no-color 2>&1 | grep -E "$BAD_PATTERNS" >/tmp/smoke-bad-lines 2>/dev/null; then
  echo "    matched lines:" >&2
  head -40 /tmp/smoke-bad-lines >&2
  rm -f /tmp/smoke-bad-lines
  fail "Found error patterns in container logs (see above)"
fi
rm -f /tmp/smoke-bad-lines

ok "logs clean"

step "Smoke test passed ✓"
