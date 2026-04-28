#!/usr/bin/env bash
# Rebuild the local docker-compose stack.
#
# Usage:
#   ./rebuild.sh                       # keep current DB, rebuild + restart app services only
#   ./rebuild.sh postgres              # switch DB to postgres (keeps its volume), rebuild apps
#   ./rebuild.sh postgres --fresh      # wipe postgres volume, start fresh
#   ./rebuild.sh --fresh               # wipe current provider's volume
#   ./rebuild.sh --full                # nuclear: teardown everything across all profiles
#   ./rebuild.sh --only backend        # only rebuild the backend image (skip frontend/internal)
#
# The expensive thing (DB container + volume) is left alone unless you ask for
# --fresh or --full. That makes inner-loop code changes fast: only the app
# images rebuild, only the app containers recreate.
#
# If a host port is already in use, see docs/troubleshooting/port-conflicts.md.
set -euo pipefail

cd "$(dirname "$0")"

# -----------------------------------------------------------------------------
# Local secrets (.env is gitignored; .env.example is the schema)
# Generate POSTGRES_PASSWORD on first run and persist it so both docker-compose
# variable substitution and subsequent runs see the same value.
# -----------------------------------------------------------------------------
ENV_FILE=".env"
if [ ! -f "$ENV_FILE" ]; then
  : > "$ENV_FILE"
fi

ensure_secret() {
  local key="$1" gen_cmd="$2"
  if grep -qE "^${key}=.+" "$ENV_FILE"; then return; fi
  local value; value="$(eval "$gen_cmd")"
  grep -v "^${key}=" "$ENV_FILE" > "$ENV_FILE.tmp" || true
  mv "$ENV_FILE.tmp" "$ENV_FILE"
  printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo "==> Generated $key and wrote it to $ENV_FILE"
}

ensure_secret POSTGRES_PASSWORD 'openssl rand -base64 24 | tr -d "=+/\n" | cut -c1-24'

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

# -----------------------------------------------------------------------------
# Args
# -----------------------------------------------------------------------------
PROVIDER=""
FRESH=0
FULL=0
ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    sqlserver|postgres) PROVIDER="$1" ;;
    --fresh)                   FRESH=1 ;;
    --full)                    FULL=1 ;;
    --only)                    ONLY="$2"; shift ;;
    -h|--help)                 sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "error: unknown arg '$1'" >&2; exit 2 ;;
  esac
  shift
done

# -----------------------------------------------------------------------------
# Detect currently running provider (if any)
# -----------------------------------------------------------------------------
detect_running() {
  for p in postgres sqlserver; do
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "projecttemplate-$p"; then
      echo "$p"; return
    fi
  done
  echo ""
}
RUNNING="$(detect_running)"

if [ -z "$PROVIDER" ]; then
  PROVIDER="${RUNNING:-postgres}"
fi

case "$PROVIDER" in
  sqlserver) DB_PROVIDER="SqlServer" ;;
  postgres)  DB_PROVIDER="Postgres" ;;
esac
export COMPOSE_PROFILES="$PROVIDER"
export DB_PROVIDER

DB_CONTAINER="projecttemplate-${PROVIDER}"
DB_VOLUME="projecttemplate_${PROVIDER}-data"
case "$PROVIDER" in
  sqlserver) DB_TIMEOUT_DEFAULT=120 ;;
  postgres)  DB_TIMEOUT_DEFAULT=60  ;;
esac
DB_TIMEOUT="${DB_TIMEOUT:-$DB_TIMEOUT_DEFAULT}"

APP_SERVICES=(backend frontend internal)
if [ -n "$ONLY" ]; then APP_SERVICES=("$ONLY"); fi

# -----------------------------------------------------------------------------
# Teardown mode (--full)
# -----------------------------------------------------------------------------
if [ "$FULL" -eq 1 ]; then
  echo "==> --full: tearing down all profiles + volumes"
  docker compose --profile sqlserver --profile postgres down --volumes --remove-orphans
  RUNNING=""
fi

# -----------------------------------------------------------------------------
# DB lifecycle
# -----------------------------------------------------------------------------
DB_ALREADY_HEALTHY=0
if [ "$FULL" -eq 0 ] && [ -n "$RUNNING" ] && [ "$RUNNING" != "$PROVIDER" ]; then
  echo "==> Switching DB: $RUNNING -> $PROVIDER (stopping old, keeping its volume)"
  docker compose --profile "$RUNNING" down --remove-orphans
fi

if [ "$FRESH" -eq 1 ]; then
  echo "==> --fresh: wiping $DB_VOLUME"
  docker compose --profile "$PROVIDER" down --volumes --remove-orphans || true
  docker volume rm "$DB_VOLUME" 2>/dev/null || true
fi

if [ "$(docker inspect -f '{{.State.Health.Status}}' "$DB_CONTAINER" 2>/dev/null || true)" = "healthy" ]; then
  echo "==> $PROVIDER is already healthy — reusing container + volume"
  DB_ALREADY_HEALTHY=1
else
  echo "==> Starting $PROVIDER"
  docker compose up -d --no-deps "$PROVIDER"

  echo "==> Waiting up to ${DB_TIMEOUT}s for $PROVIDER to become healthy"
  deadline=$(( $(date +%s) + DB_TIMEOUT ))
  while :; do
    status=$(docker inspect -f '{{.State.Health.Status}}' "$DB_CONTAINER" 2>/dev/null || echo "missing")
    case "$status" in
      healthy)  echo "    $PROVIDER: healthy"; break ;;
      missing)  echo "    $DB_CONTAINER container missing"; exit 1 ;;
      *)        printf '\r    %s: %-12s (%ds left) ' "$PROVIDER" "$status" "$(( deadline - $(date +%s) ))" ;;
    esac
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo; echo "!! $PROVIDER did not become healthy within ${DB_TIMEOUT}s"
      docker compose logs --tail=60 "$PROVIDER"
      exit 1
    fi
    sleep 3
  done
fi

# -----------------------------------------------------------------------------
# App services (always rebuilt + recreated; that's the inner-loop target)
# -----------------------------------------------------------------------------
echo "==> docker compose build ${APP_SERVICES[*]}"
docker compose build "${APP_SERVICES[@]}"

echo "==> docker compose up -d --force-recreate --no-deps ${APP_SERVICES[*]}"
docker compose up -d --force-recreate --no-deps "${APP_SERVICES[@]}"

# -----------------------------------------------------------------------------
# Status table
# -----------------------------------------------------------------------------
echo "==> docker compose ps"
docker compose ps

link() {
  local url="$1" text="${2:-$1}"
  printf '\e]8;;%s\e\\%s\e]8;;\e\\' "$url" "$text"
}
row() { printf '  %-38s  %-10s  %-10s  %s\n' "$(link "$1")" "$2" "$3" "$4"; }

echo
echo "Provider: $DB_PROVIDER $( [ "$DB_ALREADY_HEALTHY" -eq 1 ] && echo '(DB reused)' )"
echo
echo "Ports"
echo "-----"
printf '  %-38s  %-10s  %-10s  %s\n' "Host (clickable)" "Container" "Service" "Purpose"
printf '  %-38s  %-10s  %-10s  %s\n' "--------------------------" "----------" "----------" "--------------------------------------"
row "http://localhost:6173" "-> :80"   "frontend"  "Public Vue UI (nginx)"
row "http://localhost:6174" "-> :3000" "internal"  "Internal Next.js UI (Node)"
row "http://localhost:6180" "-> :8080" "backend"   ".NET API (Kestrel on :8080)"
case "$PROVIDER" in
  sqlserver)
    row "tcp://localhost:6433" "-> :1433" "sqlserver" "Azure SQL Edge (sa / LocalDev!1234)"
    ;;
  postgres)
    row "tcp://localhost:6432" "-> :5432" "postgres"  "PostgreSQL 16 (postgres / \$POSTGRES_PASSWORD from .env)"
    ;;
esac

echo
echo "Open in browser:"
printf '  %-18s %s\n' "Frontend"         "$(link http://localhost:6173)"
printf '  %-18s %s\n' "Internal"         "$(link http://localhost:6174)"
printf '  %-18s %s\n' "Backend health"   "$(link http://localhost:6180/api/health)"
printf '  %-18s %s   (Development only)\n' "Backend API docs" "$(link http://localhost:6180/scalar)"

echo
echo "Next runs:"
echo "  ./rebuild.sh                 # keep $DB_PROVIDER DB, rebuild apps only (fast)"
echo "  ./rebuild.sh <provider>      # switch DB (postgres|sqlserver)"
echo "  ./rebuild.sh --fresh         # wipe current DB volume and restart"
echo "  ./rebuild.sh --full          # nuke everything and start over"
echo "  ./rebuild.sh --only backend  # rebuild only backend (skip frontend/internal)"
