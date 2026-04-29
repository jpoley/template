# Infrastructure (Terraform)

Azure deployment: Container Apps + a managed database (Postgres or SQL Server, or an in-memory dev mode) + Container Registry + Front Door + Log Analytics + App Insights.

All environment-specific inputs are Terraform variables (see `variables.tf`). Non-secret examples go in `terraform.tfvars.example`; copy to `terraform.tfvars` and fill in.

## One-time setup

1. **Remote state**: uncomment the `backend "azurerm"` block in `providers.tf` and create the state storage account first (see [official guide](https://learn.microsoft.com/azure/developer/terraform/store-state-in-azure-storage)).
2. **Service principal for CI**: create an SP with `Contributor` (+ `User Access Administrator` if you need the role-assignment for the managed identity) on the target subscription, and add its output as `AZURE_CREDENTIALS` in GitHub repo secrets.

## Usage

```bash
# interactive — one command from clean clone to live deployment
./deploy.sh --apply

# or manual:
cd infra
cp terraform.tfvars.example terraform.tfvars  # fill in
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

`deploy.sh` is an interactive wizard: it asks ~6 questions (project, env, region, db, internal, frontdoor), writes `terraform.tfvars` + a gitignored `secrets.auto.tfvars` (DB password), then under `--apply` creates the ACR, builds + pushes the app images via `az acr build`, and applies the full stack. `--non-interactive` reads everything from flags / env for CI.

## Deployment toggles

| Variable | Default | Effect |
| --- | --- | --- |
| `db_provider` | `postgres` | `postgres` (Flexible Server), `sqlserver` (Azure SQL Database), or `none` (in-memory; dev only). The backend's `Database:Provider` and connection string env var are set automatically. |
| `deploy_internal` | `true` | Deploy the internal (Next.js) Container App. When `false`, no internal app is created and Front Door drops the `/internal/*` route. |
| `deploy_frontdoor` | `true` | Front Door + WAF in front of Container Apps. When `false`, app ingress FQDNs are returned directly via outputs. |

## Layout

```
infra/
├── providers.tf
├── variables.tf              # every env-specific value is a var
├── main.tf                   # wires modules together
├── outputs.tf
├── terraform.tfvars.example  # template — copy to terraform.tfvars
└── modules/
    ├── observability/        # Log Analytics + App Insights
    ├── registry/             # Azure Container Registry
    ├── postgres/             # PostgreSQL Flexible Server + database + firewall rule
    ├── mssql/                # Azure SQL Server + database + firewall rule
    ├── container_apps/       # Container Apps env + apps + managed identity
    └── frontdoor/            # Front Door profile + routes + optional internal WAF
```

## Image pipeline

Terraform references image tags as variables (`backend_image`, etc.). CI pushes images to ACR *before* `terraform apply`:

1. GitHub Actions builds frontend/backend/internal images.
2. Tags with `${{ github.sha }}`.
3. Pushes to `${acr_login_server}/projecttemplate/<service>:<sha>`.
4. Calls `terraform apply -var backend_image=... -var frontend_image=... -var internal_image=...`.

## Notes

- Role assignment to the user-assigned identity requires the caller to have `User Access Administrator` (or `Owner`) for the `AcrPull` binding. A `Contributor` CI principal can skip that single role assignment and grant it manually once.
- The DB admin password is a sensitive Terraform variable (`db_administrator_password`). Supply it via `TF_VAR_db_administrator_password` or a gitignored `*.auto.tfvars` file — never commit the value. `deploy.sh` writes this to `secrets.auto.tfvars` (mode 600) automatically.
- The backend receives the Postgres connection string as a Container App secret (`ConnectionStrings__Postgres`), injected from the module output. To move to AAD-token auth later, add `active_directory_auth_enabled = true` on the server and swap the env wiring for a managed-identity token provider.
- Local dev Postgres lives in `docker-compose.yml` in the repo root — it does not run in Azure.
