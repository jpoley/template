# Deploy this template to Azure

The promise: clone the template, run one command, get a working stack.

```bash
brew install terraform azure-cli
az login
cd infra && ./deploy.sh --apply
```

The wizard asks ~6 questions, creates everything in your subscription (resource group → ACR → builds and pushes images → database → Container Apps → Front Door), and prints the URLs. ~15 minutes the first time, ~3 minutes on subsequent applies (image bases get cached).

> If you only want to look at the plan first, use `--plan` instead of `--apply`. If you want to generate `terraform.tfvars` and run Terraform yourself, just `./deploy.sh` (no flag).

---

## What gets built

| Resource | Module | Notes |
| --- | --- | --- |
| Resource group `rg-{project}-{env}` | `main.tf` | Tagged with project / env / `managed_by=terraform` |
| Log Analytics workspace + App Insights | `modules/observability` | Container Apps logs flow here |
| Azure Container Registry | `modules/registry` | Apps pull via user-assigned managed identity (no admin user) |
| PostgreSQL Flexible Server **or** Azure SQL Database | `modules/postgres` / `modules/mssql` | Skipped when `db_provider = none` |
| Container Apps environment + 2-3 apps | `modules/container_apps` | Backend gets `Database__Provider` + connection-string secret |
| Front Door profile + endpoint + WAF | `modules/frontdoor` | Skipped when `deploy_frontdoor = false`; optional admin IP allowlist |

`outputs.tf` surfaces the resource group, ACR login server, DB FQDN, and the public URLs (Front Door endpoint when enabled, otherwise the Container App ingress FQDN).

## Choices the wizard asks

| Variable | Choices | Default |
| --- | --- | --- |
| `project_name` | 3-15 lowercase alphanumerics | `projecttemplate` |
| `environment` | `dev` / `staging` / `prod` | `dev` |
| `location` | any Azure region | `eastus2` |
| `db_provider` | `postgres` / `sqlserver` / `none` | `postgres` |
| `deploy_admin` | `true` / `false` | `true` |
| `deploy_frontdoor` | `true` / `false` (raw Container App ingress when `false`) | `true` |
| `postgres_sku_name` | e.g. `B_Standard_B1ms`, `GP_Standard_D2s_v3` | `B_Standard_B1ms` |
| `sqlserver_database_sku` | e.g. `Basic`, `S0`, `GP_S_Gen5_2` | `S0` |
| `admin_allowed_ips` | CIDRs allowed to hit `/admin/*` (empty = open) | `[]` |

> `deploy_frontdoor = false` removes the WAF, the admin IP allowlist, and the single hostname — it does not make the Container App ingresses private. They stay reachable on `*.azurecontainerapps.io`.

---

## Image bases — three modes

The slow part of any cloud build is restoring NuGet packages and `bun install`. The template factors that into a per-service "base image" (`Dockerfile.base`) that's built rarely and reused. **Defaults are local-first** — the template never depends on an external registry being up.

| Mode | Flag | What happens |
| --- | --- | --- |
| **Build the bases in your ACR** (default) | _(none)_ or `--build-base` | `deploy.sh` builds the three bases in your own ACR via `az acr build`. Self-contained — only external dependency is the upstream SDK/bun pull (which any docker build needs). ~15 min the first time, ~3 min after (deps cached). |
| **Use prebuilt bases from a registry you trust** | `--prebuilt-base <prefix>` | App builds `FROM <prefix>/<svc>:<tag>`. Faster bootstrap. Use this when you've published bases to your own GHCR / Artifact Registry / internal ACR. The template ships an example workflow (`base-images.yml`) you can point at any registry — there is no "official" base image registry to depend on. |
| **No base, build from upstream** | `--no-base` | App builds `FROM mcr.microsoft.com/dotnet/sdk:10.0` / `oven/bun:1` directly. Slowest (full restore on every deploy) but nothing extra to manage. |

Bases are only ever rebuilt when their inputs change — `Dockerfile.base`, `*.csproj`, `Directory.Packages.props`, `package.json`, `bun.lock`, or the enterprise CA. There is no scheduled rebuild, ever.

The same `Dockerfile.base` files are consumed three ways:
- **Cloud:** `deploy.sh` → `az acr build` → your ACR
- **CI:** `.github/workflows/base-images.yml` → push to wherever you want (GHCR, ACR, …) when deps change
- **Local dev:** `scripts/build-bases.sh` → `projecttemplate/<svc>-base:local` images on your laptop. `rebuild.sh` and `smoke.sh` call this for you.

Local docker-compose builds use the local base when present (faster inner loop) and fall back to upstream when not (cold builds still work). Pass `--skip-bases` to either script to opt out.

---

## Prerequisites

| Tool | Why | Install |
| --- | --- | --- |
| `terraform` ≥ 1.9 | runs the plan/apply | `brew install terraform` |
| `az` CLI | wizard authenticates via your `az login` session | `brew install azure-cli` |
| Azure subscription with **Contributor** | provisioning resources | — |
| **User Access Administrator** (one-time) | binding the `AcrPull` role to the apps' managed identity | grant on the target subscription, or pre-create the role assignment |

```bash
az login
az account set --subscription "<subscription-id-or-name>"
```

You don't need Docker. `deploy.sh` uses `az acr build` to build images server-side in Azure.

If you also want a remote backend (recommended for any shared environment):

```bash
az group create -n rg-tfstate -l eastus2
az storage account create -n tfstate$RANDOM -g rg-tfstate -l eastus2 --sku Standard_LRS
az storage container create --name tfstate --account-name <storage-account>
```

then uncomment the `backend "azurerm"` block in `providers.tf` and fill in the values.

---

## How `deploy.sh --apply` actually works

```
phase 1   terraform init
          terraform apply -target=module.registry  →  ACR exists
phase 2   az acr build -f Dockerfile.base × 3      →  base images in ACR
          (skipped with --prebuilt-base or --no-base)
phase 3   az acr build -f Dockerfile × 3           →  app images in ACR
          (each --build-arg BASE_IMAGE=<base ref from phase 2 / 0>)
phase 4   terraform plan
          (asks y/n)
          terraform apply                          →  full stack live
```

After phase 1 the script reads the actual ACR FQDN from Terraform output, so the image refs it uses (and writes to `images.auto.tfvars`) match exactly what got created.

## CI / non-interactive

```bash
./deploy.sh --non-interactive --apply --force \
  --project-name myapp --environment prod --location eastus2 \
  --db postgres \
  --image-tag "$GIT_SHA" \
  --admin-ips 203.0.113.0/24 \
  --db-password "$DB_ADMIN_PASSWORD"
# Add --prebuilt-base <your-registry>/template-base if you publish bases yourself.
```

`./deploy.sh --help` lists every flag and the matching env var.

## Generate tfvars only (no Azure work)

```bash
./deploy.sh                # writes terraform.tfvars + secrets.auto.tfvars, exits
```

You'd use this if your CI builds and pushes images and you want it to call `terraform apply` itself. Image refs in the generated `terraform.tfvars` are placeholders — your CI is expected to overwrite them at apply time (`-var backend_image=...`).

---

## Common first-deploy errors

| Symptom | Cause | Fix |
| --- | --- | --- |
| `acrXXXX is already in use` | ACR names are globally unique across all of Azure | Pick a different `project_name` or `environment` (the random suffix usually keeps you safe — collision means another tenant chose the same prefix already) |
| `The subscription is not registered to use namespace 'Microsoft.App'` | Container Apps not enabled in this subscription | `az provider register --namespace Microsoft.App` (and `Microsoft.OperationalInsights`, `Microsoft.ContainerRegistry`, `Microsoft.DBforPostgreSQL`) |
| `Authorization failed … role 'AcrPull'` in the apps module | Calling SP/user lacks `User Access Administrator` for the role binding | Grant `User Access Administrator`, or create the assignment manually and `terraform apply` again |
| `Cannot retrieve image … unauthorized` in Container App revisions | Images weren't pushed before phase 4 (manual flow) | Re-run `./deploy.sh --apply`, or push images to the ACR shown in `terraform output container_registry` and rerun `terraform apply` |
| Front Door returns 404 immediately after apply | Health probes haven't converged yet | Wait 5-10 minutes; usually clears on its own. Hit the Container App FQDN directly to confirm the app is up |
| `db_administrator_password must be set when db_provider != "none"` | The precondition fired because `secrets.auto.tfvars` is missing | Run `deploy.sh` again (it generates it), or `export TF_VAR_db_administrator_password=...` |

---

## Layout

```
infra/
├── deploy.sh                 ← interactive wizard + bootstrap
├── providers.tf              ← terraform + azurerm versions, optional remote state
├── variables.tf              ← every env-specific value is a var
├── main.tf                   ← wires modules together (with toggles)
├── outputs.tf
├── terraform.tfvars.example  ← copy → terraform.tfvars (gitignored)
└── modules/
    ├── observability/        Log Analytics + App Insights
    ├── registry/             Azure Container Registry
    ├── postgres/             PostgreSQL Flexible Server + database + firewall
    ├── mssql/                Azure SQL Server + database + firewall
    ├── container_apps/       Container Apps env + 2-3 apps + managed identity
    └── frontdoor/            Front Door profile + routes + optional admin WAF
```

Companion files at the repo root:

```
backend/Dockerfile.base       slow layer (SDK + restored NuGet) — built by deploy.sh / base-images.yml
frontend/Dockerfile.base      slow layer (bun install)
admin/Dockerfile.base         slow layer (bun install) — separate from frontend on purpose
.github/workflows/base-images.yml   example: publishes bases to ghcr.io on dep changes (point it at any registry)
.github/workflows/build-images.yml  builds app images, picks base via vars.BASE_IMAGE_PREFIX (unset = upstream)
scripts/build-bases.sh        local helper — builds bases on your machine for fast inner-loop docker compose
```

---

## Costs (rough order of magnitude, eastus2 list pricing)

A "minimum useful" config (postgres, admin, Front Door, B-tier everything) is roughly **~$60-90/mo** sitting idle:

| Resource | ~Cost / mo |
| --- | --- |
| Container Apps (3 apps, mostly idle) | $5-15 |
| Container Apps environment | $0 (consumption) |
| PostgreSQL Flexible Server `B_Standard_B1ms` | $15-25 |
| Azure SQL Database `S0` (alt) | $15 |
| Azure Container Registry Basic | $5 |
| Log Analytics PerGB2018 (low traffic) | $0-5 |
| App Insights | $0-5 |
| Front Door Standard | $35 base + $0.01/GB |

Skip Front Door (`--no-frontdoor`) and the admin app (`--no-admin`) for the cheapest dev box. Use `db_provider = none` for ephemeral demos with no data.

---

## After apply — smoke test

```bash
terraform output                             # see the URLs
curl -s "$(terraform output -raw backend_url)/health" | jq
open "$(terraform output -raw frontend_url)"
```

Front Door's first deployment can take 5-10 minutes for routes to converge; `404` immediately after `apply` is usually a propagation issue, not a config one.

## Teardown

```bash
cd infra
terraform destroy
```

If the resource group lingers because of `prevent_deletion_if_contains_resources = true`:

```bash
az group delete -n "$(terraform output -raw resource_group)" --yes
```

---

## Notes / gotchas

- **AcrPull role assignment** requires `User Access Administrator` (or `Owner`). A pure `Contributor` SP will fail at `azurerm_role_assignment.acr_pull` — pre-create the binding manually in that case.
- **DB password rotation** — change `db_administrator_password`, run `terraform apply`. The Container App rolls automatically because the secret value changed.
- **Move to AAD-token DB auth later** — flip `active_directory_auth_enabled = true` on the server module and replace the connection-string env wiring with a managed-identity token provider in the backend.
- **Local dev DB** — `docker-compose.yml` in the repo root runs Postgres locally. It does not run in Azure.
- The `terraform_data.validate_db_password` resource fails plan/apply early if `db_provider != none` and no password was supplied — it's a guard, not a real resource.
