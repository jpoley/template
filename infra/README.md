# Infrastructure (Terraform)

Azure deployment: Container Apps + Cosmos DB + Container Registry + Front Door + Log Analytics + App Insights.

All environment-specific inputs are Terraform variables (see `variables.tf`). Non-secret examples go in `terraform.tfvars.example`; copy to `terraform.tfvars` and fill in.

## One-time setup

1. **Remote state**: uncomment the `backend "azurerm"` block in `providers.tf` and create the state storage account first (see [official guide](https://learn.microsoft.com/azure/developer/terraform/store-state-in-azure-storage)).
2. **Service principal for CI**: create an SP with `Contributor` (+ `User Access Administrator` if you need the role-assignment for the managed identity) on the target subscription, and add its output as `AZURE_CREDENTIALS` in GitHub repo secrets.

## Usage

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars  # fill in

terraform init
terraform plan -out tfplan
terraform apply tfplan
```

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
    ├── cosmos/               # Cosmos DB account + database + container
    ├── container_apps/       # Container Apps env + 3 apps + managed identity
    └── frontdoor/            # Front Door profile + routes + optional admin WAF
```

## Image pipeline

Terraform references image tags as variables (`backend_image`, etc.). CI pushes images to ACR *before* `terraform apply`:

1. GitHub Actions builds frontend/backend/admin images.
2. Tags with `${{ github.sha }}`.
3. Pushes to `${acr_login_server}/projecttemplate/<service>:<sha>`.
4. Calls `terraform apply -var backend_image=... -var frontend_image=... -var admin_image=...`.

## Notes

- Role assignment to the user-assigned identity requires the caller to have `User Access Administrator` (or `Owner`). If your CI principal is just `Contributor`, do the Cosmos RBAC assignment once manually and remove `azurerm_cosmosdb_sql_role_assignment` from state.
- The Cosmos emulator for local dev lives in `docker-compose.yml` in the repo root — it does not run in Azure.
