# Architecture

## Runtime topology (Azure)

```mermaid
flowchart TB
  subgraph Edge[Azure Front Door]
    AFD
  end
  subgraph ACA[Container Apps Environment]
    FE[frontend]
    Admin[admin]
    API[backend]
  end
  AFD -->|/| FE
  AFD -->|/admin| Admin
  AFD -->|/api| API
  API --> PG[(Azure Database for PostgreSQL<br/>Flexible Server)]
  API --> KV[Key Vault]
  API --> AI[App Insights]
```

- **Azure Front Door** — global edge, TLS, WAF, path-based routing.
- **Container Apps** — all three containers (frontend, admin, backend) in the same environment; scale independently.
- **Azure Database for PostgreSQL (Flexible Server)** — single server per environment, one database (`projecttemplate`). Connection string injected as a Container App secret. Swap to AAD-token auth via `active_directory_auth_enabled` when ready.
- **Key Vault** — secrets (connection strings, API keys). Container Apps uses user-assigned managed identity to pull.
- **Application Insights** — traces/metrics/logs. Backend ships via OpenTelemetry/Serilog.

## Environments

At minimum `dev` and `prod`. Same Terraform, different `.tfvars`. Optional `staging` for release candidates.

## CI/CD

GitHub Actions:
- **PR checks**: lint + test + build per stack.
- **Main → dev**: build images, push to ACR, deploy via Container Apps revision.
- **Release tag → prod**: same, gated on approval environment.

## Security

- Managed identity over secrets wherever Azure supports it (ACR pull, Key Vault, Storage). Postgres uses password auth by default; flip to AAD auth for production.
- Admin UI behind Entra ID or IP allowlist at Front Door.
- All containers run as non-root.
