#!/usr/bin/env bash
# infra/deploy.sh — interactive wizard that takes you from a clean clone to a
# working Azure deployment of this template.
#
# What it does:
#   1. asks you ~6 questions (project, env, region, db, internal, frontdoor)
#   2. writes terraform.tfvars + (gitignored) secrets.auto.tfvars
#   3. when --apply: bootstraps Azure end-to-end:
#        phase 1  terraform apply -target=module.registry  (creates ACR only)
#        phase 2  az acr build the three app images
#        phase 3  terraform apply                          (full stack now images exist)
#
# Usage:
#   ./deploy.sh                           interactive, generates tfvars only
#   ./deploy.sh --plan                    + builds images and runs terraform plan
#   ./deploy.sh --apply                   + full bootstrap to Azure
#   ./deploy.sh --non-interactive --apply ...   CI mode
#   ./deploy.sh --help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TFVARS="${SCRIPT_DIR}/terraform.tfvars"
SECRETS_TFVARS="${SCRIPT_DIR}/secrets.auto.tfvars"
IMAGES_TFVARS="${SCRIPT_DIR}/images.auto.tfvars"

# --- defaults (overridable by env or flags) -----------------------------
PROJECT_NAME="${PROJECT_NAME:-projecttemplate}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
LOCATION="${LOCATION:-eastus2}"
DB_PROVIDER="${DB_PROVIDER:-postgres}"        # postgres|sqlserver|none
DEPLOY_INTERNAL="${DEPLOY_INTERNAL:-true}"
DEPLOY_FRONTDOOR="${DEPLOY_FRONTDOOR:-true}"
POSTGRES_SKU="${POSTGRES_SKU:-B_Standard_B1ms}"
SQLSERVER_SKU="${SQLSERVER_SKU:-S0}"
DB_LOGIN="${DB_LOGIN:-dbadmin}"
DB_PASSWORD="${DB_PASSWORD:-}"                # generated if empty
BACKEND_IMAGE="${BACKEND_IMAGE:-}"            # only used when ACTION=none
FRONTEND_IMAGE="${FRONTEND_IMAGE:-}"
INTERNAL_IMAGE="${INTERNAL_IMAGE:-}"
INTERNAL_ALLOWED_IPS="${INTERNAL_ALLOWED_IPS:-}" # comma-separated CIDRs
TAG_OWNER="${TAG_OWNER:-platform-team}"
IMAGE_TAG="${IMAGE_TAG:-}"                    # default: GIT_SHA-or-utc-timestamp

INTERACTIVE=true
ACTION=none           # none|plan|apply
FORCE_OVERWRITE=false

# --- helpers ------------------------------------------------------------
c_red()    { printf '\033[31m%s\033[0m' "$*"; }
c_green()  { printf '\033[32m%s\033[0m' "$*"; }
c_yellow() { printf '\033[33m%s\033[0m' "$*"; }
c_bold()   { printf '\033[1m%s\033[0m' "$*"; }

die()  { echo "$(c_red ERROR): $*" >&2; exit 1; }
note() { echo "  $(c_yellow →) $*"; }
ok()   { echo "  $(c_green ✓) $*"; }
hr()   { echo; echo "$(c_bold "──── $1 ────")"; }

ask() {
  local prompt="$1" default="${2:-}" reply
  if ! $INTERACTIVE; then
    printf '%s\n' "$default"
    return
  fi
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " reply || true
    printf '%s\n' "${reply:-$default}"
  else
    read -r -p "$prompt: " reply || true
    printf '%s\n' "$reply"
  fi
}

ask_choice() {
  local prompt="$1" default="$2"; shift 2
  local opts=("$@") reply
  if ! $INTERACTIVE; then printf '%s\n' "$default"; return; fi
  while true; do
    reply=$(ask "$prompt ($(IFS=/; echo "${opts[*]}"))" "$default")
    for o in "${opts[@]}"; do [[ "$reply" == "$o" ]] && { printf '%s\n' "$reply"; return; }; done
    echo "  Pick one of: ${opts[*]}" >&2
  done
}

ask_yesno() {
  local prompt="$1" default_bool="$2"
  local default_str
  default_str=$([[ "$default_bool" == true ]] && echo y || echo n)
  if ! $INTERACTIVE; then printf '%s\n' "$default_bool"; return; fi
  local reply
  reply=$(ask "$prompt (y/n)" "$default_str")
  case "${reply,,}" in
    y|yes) echo true ;;
    n|no)  echo false ;;
    *)     echo "$default_bool" ;;
  esac
}

gen_password() {
  # 24 chars, mixed case + digit + symbol — Azure SQL/PG admin password rules.
  local lower upper digit sym rest pw
  lower=$(LC_ALL=C tr -dc 'a-z' </dev/urandom | head -c 6)
  upper=$(LC_ALL=C tr -dc 'A-Z' </dev/urandom | head -c 6)
  digit=$(LC_ALL=C tr -dc '0-9' </dev/urandom | head -c 4)
  sym=$(LC_ALL=C tr -dc '!@#%^*_+-' </dev/urandom | head -c 4)
  rest=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 4)
  pw="${lower}${upper}${digit}${sym}${rest}"
  printf '%s' "$pw" | fold -w1 | awk 'BEGIN{srand()} {print rand() "\t" $0}' | sort -k1,1 | cut -f2 | tr -d '\n'
}

usage() {
  cat <<USAGE
infra/deploy.sh — go from clean clone to a working Azure deployment.

USAGE:
  ./deploy.sh                          interactive wizard, generates tfvars only
  ./deploy.sh --plan                   + builds images and runs terraform plan
  ./deploy.sh --apply                  + full bootstrap (creates ACR, builds + pushes images, applies)
  ./deploy.sh --non-interactive --apply ...   CI mode

OPTIONS:
  --plan                 build images then terraform plan
  --apply                full bootstrap (asks before final apply)
  --non-interactive      skip prompts; use defaults / env vars / flags
  --force                overwrite an existing terraform.tfvars without asking
  --help, -h             this help

NON-INTERACTIVE / CI inputs (also accepted as env vars):
  --project-name NAME           (PROJECT_NAME)
  --environment ENV             dev|staging|prod (ENVIRONMENT)
  --location REGION             Azure region (LOCATION)
  --db postgres|sqlserver|none  (DB_PROVIDER)
  --[no-]internal               deploy internal app (DEPLOY_INTERNAL)
  --[no-]frontdoor              deploy Front Door (DEPLOY_FRONTDOOR)
  --postgres-sku SKU            (POSTGRES_SKU)
  --sqlserver-sku SKU           (SQLSERVER_SKU)
  --db-login LOGIN              admin login (DB_LOGIN)
  --db-password PW              admin password; generated if empty (DB_PASSWORD)
  --image-tag TAG               tag for built images; default GIT_SHA or UTC timestamp (IMAGE_TAG)
  --backend-image REF           skip building backend, use this exact ref (BACKEND_IMAGE)
  --frontend-image REF          skip building frontend, use this exact ref (FRONTEND_IMAGE)
  --internal-image REF          skip building internal, use this exact ref (INTERNAL_IMAGE)
  --internal-ips a,b,c          CIDRs allowed to hit /internal (INTERNAL_ALLOWED_IPS)

OUTPUTS:
  terraform.tfvars              non-secret config; safe to commit if you want
  secrets.auto.tfvars           DB password (mode 600, gitignored)
  images.auto.tfvars            real ACR image refs after build (gitignored)
USAGE
}

# --- parse flags --------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)   ACTION=plan ;;
    --apply)  ACTION=apply ;;
    --non-interactive) INTERACTIVE=false ;;
    --force)  FORCE_OVERWRITE=true ;;
    --help|-h) usage; exit 0 ;;
    --image-tag)
      [[ $# -ge 2 ]] || die "--image-tag requires a value"
      IMAGE_TAG="$2"; shift ;;
    --project-name)
      [[ $# -ge 2 ]] || die "--project-name requires a value"
      PROJECT_NAME="$2"; shift ;;
    --environment)
      [[ $# -ge 2 ]] || die "--environment requires a value (dev|staging|prod)"
      ENVIRONMENT="$2"; shift ;;
    --location)
      [[ $# -ge 2 ]] || die "--location requires an Azure region"
      LOCATION="$2"; shift ;;
    --db)
      [[ $# -ge 2 ]] || die "--db requires a value (postgres|sqlserver|none)"
      DB_PROVIDER="$2"; shift ;;
    --internal)        DEPLOY_INTERNAL=true ;;
    --no-internal)     DEPLOY_INTERNAL=false ;;
    --frontdoor)       DEPLOY_FRONTDOOR=true ;;
    --no-frontdoor)    DEPLOY_FRONTDOOR=false ;;
    --postgres-sku)
      [[ $# -ge 2 ]] || die "--postgres-sku requires a value"
      POSTGRES_SKU="$2"; shift ;;
    --sqlserver-sku)
      [[ $# -ge 2 ]] || die "--sqlserver-sku requires a value"
      SQLSERVER_SKU="$2"; shift ;;
    --db-login)
      [[ $# -ge 2 ]] || die "--db-login requires a value"
      DB_LOGIN="$2"; shift ;;
    --db-password)
      [[ $# -ge 2 ]] || die "--db-password requires a value"
      DB_PASSWORD="$2"; shift ;;
    --backend-image)
      [[ $# -ge 2 ]] || die "--backend-image requires a ref"
      BACKEND_IMAGE="$2"; shift ;;
    --frontend-image)
      [[ $# -ge 2 ]] || die "--frontend-image requires a ref"
      FRONTEND_IMAGE="$2"; shift ;;
    --internal-image)
      [[ $# -ge 2 ]] || die "--internal-image requires a ref"
      INTERNAL_IMAGE="$2"; shift ;;
    --internal-ips)
      [[ $# -ge 2 ]] || die "--internal-ips requires a comma-separated CIDR list"
      INTERNAL_ALLOWED_IPS="$2"; shift ;;
    *) die "unknown flag: $1 (try --help)" ;;
  esac
  shift
done

# --- intro --------------------------------------------------------------
if $INTERACTIVE; then
  cat <<'EOF'

╭───────────────────────────────────────────────────────────╮
│  Template stack → Azure                                   │
│  Wizard generates terraform.tfvars + (optionally) deploys │
╰───────────────────────────────────────────────────────────╯
EOF
fi

# --- prereq sanity ------------------------------------------------------
command -v terraform >/dev/null || die "terraform not on PATH (https://developer.hashicorp.com/terraform/install)"
if [[ "$ACTION" != none ]]; then
  command -v az >/dev/null || die "az CLI not on PATH (https://learn.microsoft.com/cli/azure/install-azure-cli)"
  if ! az account show >/dev/null 2>&1; then
    die "az not logged in. Run: az login   then retry."
  fi
  SUB=$(az account show --query '{name:name, id:id}' -o tsv | tr '\t' ' ')
  ok "Azure context: $SUB"
fi

# --- existing tfvars ----------------------------------------------------
if [[ -f "$TFVARS" && "$FORCE_OVERWRITE" != true ]]; then
  if $INTERACTIVE; then
    answer=$(ask "$(c_yellow "terraform.tfvars exists.") Overwrite? (y/n)" n)
    [[ "${answer,,}" =~ ^y ]] || die "aborted (use --force to overwrite without prompt)"
  else
    die "terraform.tfvars exists; pass --force to overwrite"
  fi
fi

# --- gather inputs ------------------------------------------------------
PROJECT_NAME=$(ask    "Project name (3-15 lowercase alnum)" "$PROJECT_NAME")
ENVIRONMENT=$(ask_choice "Environment" "$ENVIRONMENT" dev staging prod)
LOCATION=$(ask        "Azure region" "$LOCATION")

DB_PROVIDER=$(ask_choice "Database" "$DB_PROVIDER" postgres sqlserver none)

if [[ "$DB_PROVIDER" == postgres ]]; then
  POSTGRES_SKU=$(ask "PostgreSQL SKU" "$POSTGRES_SKU")
elif [[ "$DB_PROVIDER" == sqlserver ]]; then
  SQLSERVER_SKU=$(ask "SQL Database SKU" "$SQLSERVER_SKU")
fi

if [[ "$DB_PROVIDER" != none ]]; then
  DB_LOGIN=$(ask "Database admin login" "$DB_LOGIN")
  if [[ -z "$DB_PASSWORD" ]]; then
    if $INTERACTIVE; then gen=$(ask_yesno "Generate a strong DB password" true); else gen=true; fi
    if [[ "$gen" == true ]]; then
      DB_PASSWORD=$(gen_password)
      ok "Generated DB password ($(c_bold "store this somewhere safe"))"
    else
      read -r -s -p "  DB admin password: " DB_PASSWORD; echo
      [[ -n "$DB_PASSWORD" ]] || die "password cannot be empty"
    fi
  fi
fi

DEPLOY_INTERNAL=$(ask_yesno "Deploy internal UI (Next.js)" "$DEPLOY_INTERNAL")
DEPLOY_FRONTDOOR=$(ask_yesno "Front Door + WAF in front of apps" "$DEPLOY_FRONTDOOR")

if [[ "$DEPLOY_INTERNAL" == true && "$DEPLOY_FRONTDOOR" == true ]]; then
  INTERNAL_ALLOWED_IPS=$(ask "Internal allowed IPs (CIDR, comma-sep, blank = open)" "$INTERNAL_ALLOWED_IPS")
fi

# --- format CIDR list for HCL ------------------------------------------
hcl_internal_ips="[]"
if [[ -n "$INTERNAL_ALLOWED_IPS" ]]; then
  hcl_internal_ips="["
  IFS=',' read -ra _ips <<<"$INTERNAL_ALLOWED_IPS"
  for ip in "${_ips[@]}"; do
    ip="${ip// /}"
    [[ -z "$ip" ]] && continue
    hcl_internal_ips+="\"${ip}\", "
  done
  hcl_internal_ips="${hcl_internal_ips%, }]"
fi

# --- image refs --------------------------------------------------------
# Two regimes:
#   ACTION=none  (wizard only): user (or CI) builds + pushes images later, so
#                we write placeholder refs into tfvars and they edit before apply.
#   ACTION!=none (we're going to apply): the ACR doesn't exist yet, so we
#                write placeholders into terraform.tfvars and overwrite with
#                real refs after phase 1 (ACR created) → images.auto.tfvars.
PLACEHOLDER_BACKEND="placeholder/backend:latest"
PLACEHOLDER_FRONTEND="placeholder/frontend:latest"
PLACEHOLDER_INTERNAL="placeholder/internal:latest"

if [[ "$ACTION" == none ]]; then
  # Suggest ACR-shaped defaults for manual editing later.
  suggested_acr="${PROJECT_NAME}${ENVIRONMENT}.azurecr.io/${PROJECT_NAME}"
  [[ -z "$BACKEND_IMAGE"  ]] && BACKEND_IMAGE="${suggested_acr}/backend:latest"
  [[ -z "$FRONTEND_IMAGE" ]] && FRONTEND_IMAGE="${suggested_acr}/frontend:latest"
  [[ -z "$INTERNAL_IMAGE" ]] && [[ "$DEPLOY_INTERNAL" == true ]] && INTERNAL_IMAGE="${suggested_acr}/internal:latest"
  if $INTERACTIVE; then
    BACKEND_IMAGE=$(ask  "Backend image"  "$BACKEND_IMAGE")
    FRONTEND_IMAGE=$(ask "Frontend image" "$FRONTEND_IMAGE")
    [[ "$DEPLOY_INTERNAL" == true ]] && INTERNAL_IMAGE=$(ask "Internal image" "$INTERNAL_IMAGE")
  fi
fi

# What gets written into terraform.tfvars right now. Real values land in
# images.auto.tfvars later when --apply/--plan runs the build.
tfvars_backend_img="$BACKEND_IMAGE"
tfvars_frontend_img="$FRONTEND_IMAGE"
tfvars_internal_img="${INTERNAL_IMAGE:-}"
if [[ "$ACTION" != none ]]; then
  tfvars_backend_img="$PLACEHOLDER_BACKEND"
  tfvars_frontend_img="$PLACEHOLDER_FRONTEND"
  tfvars_internal_img="$PLACEHOLDER_INTERNAL"
fi

# --- write terraform.tfvars --------------------------------------------
{
  cat <<EOF
# Generated by infra/deploy.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Safe to commit (no secrets). DB password lives in secrets.auto.tfvars.
# Real image refs land in images.auto.tfvars after build (both gitignored).

project_name = "${PROJECT_NAME}"
environment  = "${ENVIRONMENT}"
location     = "${LOCATION}"

db_provider      = "${DB_PROVIDER}"
deploy_internal  = ${DEPLOY_INTERNAL}
deploy_frontdoor = ${DEPLOY_FRONTDOOR}

backend_image  = "${tfvars_backend_img}"
frontend_image = "${tfvars_frontend_img}"
internal_image = "${tfvars_internal_img}"
EOF
  if [[ "$DB_PROVIDER" == postgres ]]; then
    cat <<EOF

postgres_sku_name = "${POSTGRES_SKU}"
EOF
  elif [[ "$DB_PROVIDER" == sqlserver ]]; then
    cat <<EOF

sqlserver_database_sku = "${SQLSERVER_SKU}"
EOF
  fi
  if [[ "$DB_PROVIDER" != none ]]; then
    cat <<EOF
db_administrator_login = "${DB_LOGIN}"
EOF
  fi
  if [[ "$DEPLOY_FRONTDOOR" == true ]]; then
    cat <<EOF

internal_allowed_ips = ${hcl_internal_ips}
EOF
  fi
  cat <<EOF

tags = {
  owner = "${TAG_OWNER}"
}
EOF
} > "$TFVARS"
ok "Wrote $TFVARS"

# --- write secrets.auto.tfvars (DB password) ---------------------------
if [[ "$DB_PROVIDER" != none ]]; then
  umask 077
  cat > "$SECRETS_TFVARS" <<EOF
# Generated by infra/deploy.sh — DO NOT COMMIT (gitignored).
db_administrator_password = "${DB_PASSWORD}"
EOF
  chmod 600 "$SECRETS_TFVARS"
  ok "Wrote $SECRETS_TFVARS (mode 600)"
fi

# --- summary -----------------------------------------------------------
echo
echo "$(c_bold "Plan summary"):"
echo "  project       $PROJECT_NAME"
echo "  environment   $ENVIRONMENT"
echo "  region        $LOCATION"
echo "  db            $DB_PROVIDER"
echo "  internal app  $DEPLOY_INTERNAL"
echo "  front door    $DEPLOY_FRONTDOOR"

# --- exit early if no terraform action requested -----------------------
if [[ "$ACTION" == none ]]; then
  echo
  note "Wizard done. Image refs in terraform.tfvars are placeholders — fill in"
  note "real refs (CI normally does this) before running:"
  note "  cd infra && terraform init && terraform plan"
  note "Or rerun with --apply to have this script bootstrap everything."
  exit 0
fi

# =======================================================================
# BOOTSTRAP — from here down we're talking to Azure
# =======================================================================
cd "$SCRIPT_DIR"

# Image tag (one tag for all images in this run).
if [[ -z "$IMAGE_TAG" ]]; then
  if [[ -n "${GIT_SHA:-}" ]]; then
    IMAGE_TAG="${GIT_SHA:0:12}"
  elif git -C "$REPO_ROOT" rev-parse --short HEAD >/dev/null 2>&1; then
    IMAGE_TAG="$(git -C "$REPO_ROOT" rev-parse --short=12 HEAD)"
  else
    IMAGE_TAG="$(date -u +%Y%m%d-%H%M%S)"
  fi
fi
ok "Image tag: $IMAGE_TAG"

# ---- Phase 1 — terraform init + targeted apply for the ACR -----------
hr "phase 1 / 3 — terraform init + create ACR"
terraform init -input=false

# -target needs all required vars; supply placeholders. They'll be ignored
# because the targeted resources don't reference them.
terraform apply -input=false -auto-approve \
  -target=module.registry \
  -target=azurerm_resource_group.main

ACR_LOGIN_SERVER="$(terraform output -raw container_registry)"
ACR_NAME="${ACR_LOGIN_SERVER%%.*}"
ok "ACR ready: $ACR_LOGIN_SERVER"

# ---- Phase 2 — app images -------------------------------------------
hr "phase 2 / 3 — app images"

# `az acr build` does not support BuildKit named build contexts, so the app
# Dockerfiles' `COPY --from=enterprise-ca …` lines need to be rewritten to a
# regular COPY against a sibling .enterprise-ca/ dir we stage into the build
# context. Local + GHA builders use named contexts directly; this rewrite is
# only for ACR-side builds.
acr_build() {
  local image="$1" dockerfile="$2" ctx="$3"; shift 3
  echo "    $(c_yellow building) $ACR_LOGIN_SERVER/$image"

  local stage
  stage="$(mktemp -d -t acrctx.XXXXXX)"
  cp -R "$ctx/." "$stage/"
  mkdir -p "$stage/.enterprise-ca"
  if [[ -d "${REPO_ROOT}/certs" ]]; then
    cp -R "${REPO_ROOT}/certs/." "$stage/.enterprise-ca/"
  fi
  # Always provide the in-image installer (no-ops when no real cert is staged).
  if [[ ! -e "$stage/.enterprise-ca/install-ca-in-image.sh" ]]; then
    printf '#!/bin/sh\nexit 0\n' > "$stage/.enterprise-ca/install-ca-in-image.sh"
    chmod +x "$stage/.enterprise-ca/install-ca-in-image.sh"
  fi
  sed -E 's#COPY --from=enterprise-ca[[:space:]]+\.[[:space:]]+#COPY .enterprise-ca/ #g; s#COPY --from=enterprise-ca[[:space:]]+#COPY .enterprise-ca/#g' \
    "$stage/$dockerfile" > "$stage/.acr.Dockerfile"

  local rc=0
  az acr build \
    --registry "$ACR_NAME" \
    --image "$image" \
    --file ".acr.Dockerfile" \
    "$@" \
    "$stage" || rc=$?
  rm -rf "$stage"
  return $rc
}

build_one_app() {
  local svc="$1"
  acr_build "${PROJECT_NAME}/${svc}:${IMAGE_TAG}" "Dockerfile" "${REPO_ROOT}/${svc}"
}

note "Building backend, frontend$([[ "$DEPLOY_INTERNAL" == true ]] && echo ", internal") in $ACR_NAME"
build_one_app backend
build_one_app frontend
[[ "$DEPLOY_INTERNAL" == true ]] && build_one_app internal

BACKEND_REAL="${ACR_LOGIN_SERVER}/${PROJECT_NAME}/backend:${IMAGE_TAG}"
FRONTEND_REAL="${ACR_LOGIN_SERVER}/${PROJECT_NAME}/frontend:${IMAGE_TAG}"
INTERNAL_REAL=""
[[ "$DEPLOY_INTERNAL" == true ]] && INTERNAL_REAL="${ACR_LOGIN_SERVER}/${PROJECT_NAME}/internal:${IMAGE_TAG}"
ok "Apps pushed."

# Write image refs to a separate tfvars so the next step picks them up.
cat > "$IMAGES_TFVARS" <<EOF
# Generated by infra/deploy.sh — DO NOT COMMIT (gitignored).
backend_image  = "${BACKEND_REAL}"
frontend_image = "${FRONTEND_REAL}"
internal_image = "${INTERNAL_REAL}"
EOF
ok "Wrote $IMAGES_TFVARS"

# ---- Phase 3 — full terraform apply ---------------------------------
hr "phase 3 / 3 — terraform apply (full stack)"

terraform plan -input=false -out tfplan

if [[ "$ACTION" == apply ]]; then
  if $INTERACTIVE; then
    answer=$(ask "$(c_bold "Apply this plan to Azure?") (y/n)" n)
    [[ "${answer,,}" =~ ^y ]] || { note "Skipped apply. tfplan saved in $SCRIPT_DIR/tfplan"; exit 0; }
  fi
  terraform apply -input=false tfplan
  echo
  ok "Done. Outputs:"
  terraform output
fi
