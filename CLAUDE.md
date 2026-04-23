# Claude / AI agent instructions

This repo is a full-stack template. Follow the conventions below when contributing.

## First thing every session

```bash
# Open a session log
./.logs/new-session.sh claude-code    # prints the file path; append JSONL as you work
```

Schema is in `.logs/README.md`. Log decisions (why, not what) and references (URLs + quotes).

## Repo map

| Path | What | Stack |
| --- | --- | --- |
| `frontend/` | Public UI | Vue 3 + TS + Bun + Tailwind 4 + shadcn-vue, PWA/service worker |
| `admin/` | Admin UI (internal) | Same stack, no service worker, `@tanstack/vue-query` |
| `backend/` | API | C# .NET 10, Minimal API, PostgreSQL (EF Core + Npgsql) |
| `infra/` | Terraform | Azure Container Apps + Azure Database for PostgreSQL + Front Door |
| `docs/` | Narrative docs (requirements, design, architecture) | Markdown |
| `backlog/` | Real backlog.md project — tasks + decisions + docs | `backlog` CLI |
| `install/` | Reproducible host bootstrap + per-project deps | Bash |
| `.logs/` | Per-session JSONL decision/reference log | — |

## Task + decision management

Use the `backlog` CLI — **do not** edit markdown in `backlog/tasks/` by hand unless the CLI is unavailable.

```bash
backlog task list
backlog task create "Title" -d "Body" --ac "Acceptance" --labels "area,priority"
backlog task edit TASK-N --status "In Progress" --assignee claude-code
backlog task edit TASK-N --status "Done"
backlog decision create "Title"
```

Architecture decisions go in `backlog/decisions/` (via `backlog decision create`). Do **not** create new ADRs under `docs/adr/` — that location is retired.

## Conventions

### Backend (.NET 10)

- Minimal API endpoints live in `src/ProjectTemplate.Api/Endpoints/*.cs`, grouped by resource. No controllers.
- Repository interfaces in `ProjectTemplate.Domain`, implementations in `ProjectTemplate.Infrastructure`.
- Domain entities are `record`s — immutable by default.
- Use source-generated logging (`[LoggerMessage]`) instead of `LogX("string {interp}", ...)` — CA1848 is opt-in at `latest-Recommended` analysis level; even at `latest` it's a perf best practice.
- `TreatWarningsAsErrors=true` in `Directory.Build.props`. `AnalysisLevel=latest` — don't raise to Recommended without suppressing the perf/globalization rules that tend to fire in templates.
- Tests use `WebApplicationFactory<Program>` + xUnit + Shouldly (FluentAssertions 8+ switched to commercial — do not upgrade).
- Postgres is the standard database. Keep repository code behind the `IItemRepository` interface — SqlServer and InMemory implementations coexist, but new features should not branch on provider.

### Frontend / admin

- Tailwind 4 + shadcn-vue. Add shadcn components with `bunx shadcn-vue@latest add <name>`.
- Server state via `@tanstack/vue-query` (admin) or `fetch` + Pinia (frontend).
- Path alias `@/` → `src/`.
- Keep the service worker in `frontend/` only — the admin UI must always be fresh.
- ESLint flat config in `eslint.config.js`. Don't revert to `.eslintrc.cjs` — eslint 9+ defaults to flat.

### Terraform

- Everything environment-specific is a `variable`. No hardcoded values.
- One module per concern under `modules/`.
- Secrets never go in `.tfvars` — use Azure Key Vault + managed identity (see `modules/container_apps`).

### Commits & PRs

- Conventional Commits: `feat:`, `fix:`, `refactor:`, `docs:`, `chore:`, `test:`, `infra:`.
- One concern per PR. If a PR touches multiple stacks, explain why.

## Pre-flight checks before claiming "done"

- `cd frontend && bun run typecheck && bun run lint && bun run build`
- `cd admin && bun run typecheck && bun run build`
- `cd backend && dotnet build -c Release && dotnet test -c Release`
- `cd infra && terraform fmt -check -recursive && terraform validate`
- `docker compose up --build` — no crash-loops.

## Don'ts

- Don't add features not requested. Three similar lines beats a premature abstraction.
- Don't add comments that restate what the code does.
- Don't bypass `--no-verify` or hook checks.
- Don't hand-edit `backlog/tasks/*.md` when the CLI can do it — the CLI maintains the index.
- Don't upgrade FluentAssertions to 8+ (commercial license). Stay on Shouldly.
- Don't add `Microsoft.Extensions.*` 10.x refs that the shared framework already provides (NU1510).
