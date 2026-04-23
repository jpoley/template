# GitHub Copilot Instructions

> These instructions are consumed by GitHub Copilot (Chat, CLI, code review). They focus on **validation & testing** — things Copilot should check before proposing or approving changes.

## Stack at a glance

- **frontend/**, **admin/** — Vue 3 + TypeScript, Bun, Tailwind 4, shadcn-vue.
- **backend/** — C# .NET 10, Minimal API, PostgreSQL (EF Core + Npgsql).
- **infra/** — Terraform, Azure (Container Apps + Azure Database for PostgreSQL + Front Door).

## Validation commands

Copilot should suggest or run these before marking a task done:

| Scope | Command |
| --- | --- |
| Frontend type check | `cd frontend && bun run typecheck` |
| Frontend lint | `cd frontend && bun run lint` |
| Frontend tests | `cd frontend && bun run test` |
| Admin type check | `cd admin && bun run typecheck` |
| Admin tests | `cd admin && bun run test` |
| Backend build | `dotnet build backend/Backend.sln /warnaserror` |
| Backend tests | `dotnet test backend/Backend.sln` |
| Backend format | `dotnet format backend/Backend.sln --verify-no-changes` |
| Terraform fmt | `terraform -chdir=infra fmt -check -recursive` |
| Terraform validate | `terraform -chdir=infra init -backend=false && terraform -chdir=infra validate` |
| Local stack smoke test | `docker compose up --build --abort-on-container-exit backend frontend admin` |

## Review rules

When reviewing a PR:

1. **Every behavior change needs a test.** Bug fixes must include a regression test.
2. **Reject comments** that restate what code does, reference the current PR, or quote ticket numbers.
3. **Reject any hardcoded secrets** or connection strings in code, `.tfvars`, `docker-compose.yml`, or `appsettings*.json`. The local Postgres password is auto-generated into `.env` (gitignored) by `./rebuild.sh`; the SqlServer SA password (`LocalDev!1234`) in the optional `sqlserver` compose profile is the only remaining hardcoded dev credential.
4. **Terraform changes must be plan-reviewed**, not just applied. Request a plan output in the PR.
5. **New npm/NuGet dependencies** require a short justification in the PR description.
6. **Schema changes** (tables, indexes, migrations) need a backlog decision (`backlog decision create`).

## Preferred patterns

- Repository interface in `Domain`, implementation in `Infrastructure`. Don't put EF Core / Npgsql types in API endpoints.
- API endpoints are mapped in `*Endpoints.cs` files inside `src/ProjectTemplate.Api/Endpoints/`. No controllers.
- Vue components: `<script setup lang="ts">` only — no Options API.
- Tailwind v4: prefer `@theme` tokens over arbitrary values.

## Anti-patterns

- `async void` in C# (except for event handlers).
- `any` in TS (use `unknown` and narrow).
- Unbounded `SELECT` / N+1 queries in hot paths — page with `.Take()` / `.Skip()` and use `.Include()` deliberately.
- Running containers as root (all Dockerfiles in this repo use a non-root user).
