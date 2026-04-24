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

One command, deterministic, runs the whole suite end-to-end:

```bash
scripts/test-all.sh
```

This runs, in order: backend `dotnet test`, frontend + admin `typecheck`/`lint`/`vitest`/`build`, `terraform fmt`/`validate`/`tflint`, then the **closed-loop smoke test** (`scripts/smoke.sh` — `docker compose up --build`, wait for services, CRUD round-trip against `/api/items`, verify frontend + admin serve HTML, scan logs for unhandled errors, `docker compose down -v`). Exits non-zero on any failure.

Full guide (including the matrix of what runs where locally vs in CI, and how to extend the suite per component) is in [`docs/testing.md`](docs/testing.md).

Rules:

- **Closed-loop smoke is non-negotiable** for feature PRs and every dependency bump (`package.json`, `.csproj`, `Directory.Packages.props`, `docker-compose.yml`). Unit tests + typecheck passed while prior library upgrades broke runtime wiring — the smoke step is the guard.
- If `scripts/test-all.sh` fails, the PR is not done. Fix the runtime issue — do not weaken the test.
- Useful flags: `--only backend|frontend|admin|infra|e2e|smoke|ci` for fast feedback, `--no-smoke` to skip the compose loop during iteration, `--with-ci` to also run every GitHub Actions workflow locally via [`act`](https://github.com/nektos/act) (opt-in because it pulls multi-GB runner images), `--keep-going` to see every failure at once.
- `scripts/ci.sh` runs `act` directly if you want to iterate on workflows without the rest of the suite. Defaults to the safe subset (excludes `build-images.yml`, which needs registry secrets); pass `--all` with a `.secrets` file to include it.
- Per-component suites live next to the code: `backend/tests/`, `frontend/src/__tests__/`, `admin/src/__tests__/`, `e2e/tests/`. Extend them when you add features — the template's contract is that every component has a test surface, not just the API.

## Don'ts

- Don't add features not requested. Three similar lines beats a premature abstraction.
- Don't add comments that restate what the code does.
- Don't bypass `--no-verify` or hook checks.
- Don't hand-edit `backlog/tasks/*.md` when the CLI can do it — the CLI maintains the index.
- Don't upgrade FluentAssertions to 8+ (commercial license). Stay on Shouldly.
- Don't add `Microsoft.Extensions.*` 10.x refs that the shared framework already provides (NU1510).
