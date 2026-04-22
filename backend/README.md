# Backend

.NET 10 Web API using Azure Cosmos DB for document storage.

## Projects

- `src/ProjectTemplate.Domain` — entities, repository interfaces. No framework dependencies.
- `src/ProjectTemplate.Infrastructure` — Cosmos DB implementation of repositories, DI registration.
- `src/ProjectTemplate.Api` — Minimal API host, endpoints, Serilog, OpenAPI/Scalar.
- `tests/ProjectTemplate.Api.Tests` — xUnit + `WebApplicationFactory` integration tests.

## Run locally

Against the Cosmos emulator (via `docker compose up cosmos`):

```bash
dotnet run --project src/ProjectTemplate.Api
```

Open http://localhost:8080/scalar for API docs (Development env only).

## Configuration

`Cosmos:*` in `appsettings.json`. Use one of:

- `Key` for emulator / local.
- `UseManagedIdentity: true` in Azure (Container Apps with a user-assigned identity and `Cosmos DB Built-in Data Contributor` role assignment).

Override per-environment via environment variables, e.g. `Cosmos__Endpoint`, `Cosmos__Key`.

## Tests

```bash
dotnet test
```

## Docker

```bash
docker build -t projecttemplate-backend .
docker run -p 8080:8080 \
  -e Cosmos__Endpoint=... \
  -e Cosmos__Key=... \
  projecttemplate-backend
```
