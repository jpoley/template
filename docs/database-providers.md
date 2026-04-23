# Database providers

The backend supports three database backends out of the box. All three are built and kept in sync at all times; selection happens at runtime via a single config key.

## Choosing a provider

Set `Database:Provider` (config key) or `Database__Provider` (env var) to one of:

| Value | Implementation | Data store |
| --- | --- | --- |
| `Cosmos` (default) | `CosmosItemRepository` — native SDK v3 | Azure Cosmos DB (SQL API) |
| `SqlServer` | `RelationalItemRepository` — EF Core | Microsoft SQL Server 2022+ |
| `Postgres` | `RelationalItemRepository` — EF Core + Npgsql | PostgreSQL 14+ |
| `InMemory` | `InMemoryItemRepository` | In-proc dictionary (tests / native dev) |

The SQL Server and Postgres implementations share a single `ItemDbContext` and `RelationalItemRepository` — only the DI wiring and connection string change.

## Local development (Docker)

Use the wrapper script:

```bash
./rebuild.sh                       # keep current DB, rebuild + restart app services only (~3s)
./rebuild.sh postgres              # switch DB (keeps old DB's volume), rebuild apps
./rebuild.sh cosmos --fresh        # wipe cosmos volume and start fresh
./rebuild.sh --fresh               # wipe current provider's volume
./rebuild.sh --full                # nuclear: teardown all profiles + volumes
./rebuild.sh --only backend        # only rebuild the backend image
```

Under the hood this sets `COMPOSE_PROFILES=<provider>` and `DB_PROVIDER=<ConfigValue>`. Each DB service is gated behind a compose profile of the same name, so only the selected container is created.

**Key behavior**: no-arg `./rebuild.sh` **does not touch the database container**. It detects which provider is running, rebuilds only the app images, and recreates only the app containers. That's the fast inner-loop path — a typical backend code change rebuilds in ~3 seconds instead of waiting for the DB to boot again. Use `--fresh` or `--full` when you actually want to wipe data.

## Schema provisioning

In `Development`, the backend calls `Database.EnsureCreatedAsync()` (relational) or `CreateDatabaseIfNotExistsAsync()` + `CreateContainerIfNotExistsAsync()` (Cosmos) on startup. That's enough for template/demo use.

For production, swap to EF Core migrations (relational) or a Bicep/Terraform-managed Cosmos account. The template deliberately does not ship migrations — they belong in the project that consumes the template, not the template itself.

## Connection strings

In `appsettings.json`:

```jsonc
{
  "Database": { "Provider": "Cosmos" },
  "ConnectionStrings": {
    "SqlServer": "Server=localhost,6433;Database=projecttemplate;User Id=sa;Password=LocalDev!1234;TrustServerCertificate=True;",
    "Postgres":  "Host=localhost;Port=6432;Database=projecttemplate;Username=postgres;Password=LocalDev!1234"
  },
  "Cosmos": {
    "Endpoint": "https://localhost:6081",
    "Key": "C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==",
    "TrustEmulatorCertificate": true
  }
}
```

Ports above match `docker-compose.yml` host mappings. In compose, the backend uses service DNS (`cosmos`, `sqlserver`, `postgres`) and the container-internal ports (8081 / 1433 / 5432).

## Notes per provider

### Cosmos (vNext preview Linux emulator)

- **Native arm64 + amd64** — no Rosetta.
- HTTP only (no TLS dance), boots in ~30s.
- The backend sets `Cosmos:IsEmulator = true` in Development, which flips the SDK into `ConnectionMode=Gateway` + `LimitToEndpoint=true`. Without this the SDK tries to follow the emulator's advertised replica addresses (`127.0.0.1`), which inside another container resolves to *itself*, not cosmos — causing the client to hang on handshake.
- If you switch to HTTPS (by setting `PROTOCOL: "https"` in compose), `IsEmulator` additionally accepts the self-signed cert.
- Never enable `IsEmulator` against a real Cosmos account.

### SQL Server (Azure SQL Edge)

- **Native arm64 + amd64** — no Rosetta.
- Image: `mcr.microsoft.com/azure-sql-edge:latest`. Microsoft's SQL Server-compatible engine with matching T-SQL surface. Updates ended Sept 2024 but the image is stable and speaks to `Microsoft.EntityFrameworkCore.SqlServer` unchanged.
- In production use real Azure SQL / Managed Instance (same provider, same EF Core code).
- Default SA password `LocalDev!1234` meets complexity requirements.
- Connection string uses `TrustServerCertificate=True` for the dev container. In Azure, use AAD auth + managed identity instead.
- No `sqlcmd` in the image — healthcheck uses a bash TCP probe on 1433. EF Core is configured with `EnableRetryOnFailure` to tolerate the brief window between "port accepting" and "engine fully ready".

### PostgreSQL 16

- **Native arm64 + amd64** images.
- Smallest footprint, fastest boot (~3s). Default choice for fast inner-loop dev if you don't need SQL Server / Cosmos semantics specifically.
- EF Core is configured with `EnableRetryOnFailure` for resilience.

## Switching providers

`./rebuild.sh <provider>` does a full `docker compose down --remove-orphans` across all three profiles first. That removes the previous DB container and any running app containers. Volumes (`cosmos-data`, `sqlserver-data`, `postgres-data`) are preserved — so switching back to a previous provider will return you to whatever data you had there last. To wipe, `docker volume rm projecttemplate_postgres-data` etc.
