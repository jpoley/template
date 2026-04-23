# Database providers

**Postgres is the standard database for this template.** SQL Server and an in-memory store are kept as alternatives — useful for tests and for teams with an existing SQL Server investment — but all new work targets Postgres.

## Choosing a provider

Set `Database:Provider` (config key) or `Database__Provider` (env var) to one of:

| Value | Implementation | Data store |
| --- | --- | --- |
| `Postgres` (default) | `RelationalItemRepository` — EF Core + Npgsql | PostgreSQL 14+ |
| `SqlServer` | `RelationalItemRepository` — EF Core | Microsoft SQL Server 2022+ |
| `InMemory` | `InMemoryItemRepository` | In-proc dictionary (tests / native dev) |

SQL Server and Postgres implementations share a single `ItemDbContext` and `RelationalItemRepository` — only the DI wiring and connection string change.

## Local development (Docker)

Use the wrapper script:

```bash
./rebuild.sh                       # keep current DB, rebuild + restart app services only (~3s)
./rebuild.sh postgres              # switch DB to postgres, rebuild apps (default)
./rebuild.sh sqlserver             # switch DB to sqlserver, rebuild apps
./rebuild.sh --fresh               # wipe current provider's volume
./rebuild.sh --full                # nuclear: teardown all profiles + volumes
./rebuild.sh --only backend        # only rebuild the backend image
```

Under the hood this sets `COMPOSE_PROFILES=<provider>` and `DB_PROVIDER=<ConfigValue>`. Each DB service is gated behind a compose profile of the same name, so only the selected container is created.

**Key behavior**: no-arg `./rebuild.sh` **does not touch the database container**. It detects which provider is running, rebuilds only the app images, and recreates only the app containers.

## Schema provisioning

In `Development`, the backend calls `Database.EnsureCreatedAsync()` on startup. That's enough for template/demo use.

For production, swap to EF Core migrations. The template deliberately does not ship migrations — they belong in the project that consumes the template, not the template itself.

## Connection strings

In `appsettings.json`:

```jsonc
{
  "Database": { "Provider": "Postgres" },
  "ConnectionStrings": {
    "Postgres":  "Host=localhost;Port=6432;Database=projecttemplate;Username=postgres;Password=<value from .env POSTGRES_PASSWORD>",
    "SqlServer": "Server=localhost,6433;Database=projecttemplate;User Id=sa;Password=LocalDev!1234;TrustServerCertificate=True;"
  }
}
```

Ports above match `docker-compose.yml` host mappings. In compose, the backend uses service DNS (`postgres`, `sqlserver`) and the container-internal ports (5432 / 1433).

The Postgres password is auto-generated into `.env` (gitignored) by `./rebuild.sh` on first run. docker-compose reads `.env` automatically, so the backend's cross-container connection string stays in sync without any hand-editing. For native dev (`dotnet run` against the Postgres container), export the same value: `export ConnectionStrings__Postgres="Host=localhost;Port=6432;Database=projecttemplate;Username=postgres;Password=$(grep '^POSTGRES_PASSWORD=' .env | cut -d= -f2)"`.

## Notes per provider

### PostgreSQL 16

- **Native arm64 + amd64** images. Smallest footprint, fastest boot (~3s).
- EF Core is configured with `EnableRetryOnFailure` for resilience.
- In production: Azure Database for PostgreSQL (Flexible Server) — same provider, same EF Core code. Connection string arrives as a Container App secret (see `infra/modules/container_apps`).

### SQL Server (Azure SQL Edge)

- **Native arm64 + amd64** — no Rosetta.
- Image: `mcr.microsoft.com/azure-sql-edge:latest`. Microsoft's SQL Server-compatible engine. Updates ended Sept 2024 but the image is stable and speaks to `Microsoft.EntityFrameworkCore.SqlServer` unchanged.
- Connection string uses `TrustServerCertificate=True` for the dev container. In Azure, use AAD auth + managed identity instead.
- No `sqlcmd` in the image — healthcheck uses a bash TCP probe on 1433. EF Core is configured with `EnableRetryOnFailure`.

## Switching providers

`./rebuild.sh <provider>` does a full `docker compose down --remove-orphans` across both profiles first. Volumes (`postgres-data`, `sqlserver-data`) are preserved — switching back returns you to whatever data you had last. To wipe, `docker volume rm projecttemplate_postgres-data` etc.
