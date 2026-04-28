# GitHub Copilot Instructions

> These instructions are consumed by GitHub Copilot (Chat, CLI, code review). They focus on **validation & testing** — things Copilot should check before proposing or approving changes.

## Stack at a glance

- **frontend/** — Vue 3 + TypeScript, Bun, Vite, Tailwind 4, shadcn-vue. Pure SPA (PWA + service worker).
- **internal/** — Next.js 15 (App Router) + React 19 + TypeScript, Bun (install/dev) + Node 22 (runtime), Tailwind 4, shadcn (React). SSR/admin-grade UI; runs as a Node standalone server.
- **backend/** — C# .NET 10, Minimal API, PostgreSQL (EF Core + Npgsql).
- **infra/** — Terraform, Azure (Container Apps + Azure Database for PostgreSQL + Front Door).

## Validation commands

Copilot should suggest or run these before marking a task done:

| Scope | Command |
| --- | --- |
| Frontend type check | `cd frontend && bun run typecheck` |
| Frontend lint | `cd frontend && bun run lint` |
| Frontend tests | `cd frontend && bun run test` |
| Internal type check | `cd internal && bun run typecheck` |
| Internal lint | `cd internal && bun run lint` |
| Internal tests | `cd internal && bun run test` |
| Internal build | `cd internal && bun run build` |
| Backend build | `dotnet build backend/Backend.sln /warnaserror` |
| Backend tests | `dotnet test backend/Backend.sln` |
| Backend format | `dotnet format backend/Backend.sln --verify-no-changes` |
| Terraform fmt | `terraform -chdir=infra fmt -check -recursive` |
| Terraform validate | `terraform -chdir=infra init -backend=false && terraform -chdir=infra validate` |
| Local stack smoke test | `docker compose up --build --abort-on-container-exit backend frontend internal` |

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
- Vue components (in `frontend/`): `<script setup lang="ts">` only — no Options API.
- React components (in `internal/`): function components + hooks. Default to React Server Components in `app/`; mark interactive components with `'use client'`. No legacy class components.
- Tailwind v4: prefer `@theme` tokens over arbitrary values.

## Anti-patterns

- `async void` in C# (except for event handlers).
- `any` in TS (use `unknown` and narrow).
- Unbounded `SELECT` / N+1 queries in hot paths — page with `.Take()` / `.Skip()` and use `.Include()` deliberately.
- Running containers as root (all Dockerfiles in this repo use a non-root user).
