# Backend

.NET 10 Web API using PostgreSQL via EF Core (Npgsql) for data storage.

## Projects

- `src/ProjectTemplate.Domain` — entities, repository interfaces. No framework dependencies.
- `src/ProjectTemplate.Infrastructure` — EF Core + Npgsql implementation of repositories, DI registration. SqlServer and in-memory implementations are included as alternatives.
- `src/ProjectTemplate.Api` — Minimal API host, endpoints, Serilog, OpenAPI/Scalar.
- `tests/ProjectTemplate.Api.Tests` — xUnit + `WebApplicationFactory` integration tests.

## Run locally

Against the Postgres container (via `docker compose --profile postgres up postgres`):

```bash
dotnet run --project src/ProjectTemplate.Api
```

Open http://localhost:6180/scalar for API docs (Development env only).

## Configuration

`ConnectionStrings:Postgres` in `appsettings.json`. Override per-environment via environment variables, e.g. `ConnectionStrings__Postgres`.

If `ConnectionStrings:Postgres` is empty in Development, the backend falls back to the in-memory store for quick native dev.

## Tests

```bash
dotnet test
```

## Docker

```bash
docker build --build-context enterprise-ca=../certs -t projecttemplate-backend .
docker run -p 6180:8080 \
  -e ConnectionStrings__Postgres="Host=...;Port=5432;Database=projecttemplate;Username=...;Password=...;SslMode=Require" \
  projecttemplate-backend
```

`--build-context enterprise-ca=../certs` satisfies the `COPY --from=enterprise-ca` line in the Dockerfile. With no `enterprise-ca.crt` staged in `../certs`, the in-image installer no-ops; with one staged, it installs into the system trust store. See [`../docs/enterprise-proxy.md`](../docs/enterprise-proxy.md).
