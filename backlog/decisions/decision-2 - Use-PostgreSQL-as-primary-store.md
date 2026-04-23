---
id: decision-2
title: Use PostgreSQL as primary store
date: '2026-04-23 00:00'
status: accepted
---
## Context

The project needs a managed, pay-for-what-you-use data store with strong transactional semantics, mature tooling, broad hosting options, and a large operational knowledge base across the team. Requirements lean relational: structured records, tenant-scoped queries, reporting, joins, unique constraints, and evolvable schemas under migrations.

## Decision

Use **PostgreSQL** as the single primary store across all environments.

- Local dev: `postgres:16-alpine` via `docker-compose.yml` (profile `postgres`).
- Production: **Azure Database for PostgreSQL — Flexible Server**, provisioned by `infra/modules/postgres`. One server per environment, one database (`projecttemplate`).
- Access path in .NET: EF Core + `Npgsql.EntityFrameworkCore.PostgreSQL`, sharing a single `ItemDbContext` with the retained SqlServer provider.

SQL Server and in-memory implementations remain in the codebase as optional providers for flexibility and for tests, but Postgres is the standard — new features target it.

## Consequences

- Mature relational feature set: transactions, joins, generated columns, JSONB, strong indexing, logical replication, rich SQL dialect.
- Migrations live with the consuming project (EF Core migrations), not in the template itself.
- Backend receives the connection string as a Container App secret. AAD-token auth is a one-flag move (`active_directory_auth_enabled = true`) when the team is ready.
- Burstable SKU default (`B_Standard_B1ms`) is cheap for dev; production should size up via the `postgres_sku_name` variable.
- The administrator password is a sensitive Terraform variable and must be supplied via `TF_VAR_postgres_administrator_password` or a gitignored `*.auto.tfvars` file.
