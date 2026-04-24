# Testing

**Mental model: one command.** `scripts/test-all.sh` runs every per-component suite plus a closed-loop docker-compose smoke test. If it exits 0, the branch is shippable. Typecheck + unit tests alone are **not** sufficient — that's what let recent dependency upgrades slip runtime breakage through.

## The three scripts

All scripts live at the repo root under `scripts/`.

### `scripts/test-all.sh` — umbrella runner

Runs every per-component check, then the closed-loop smoke test. This is the pre-flight gate before claiming a PR is done.

```bash
scripts/test-all.sh                 # everything, short-circuit on first failure
scripts/test-all.sh --no-smoke      # fast feedback: skip the docker compose loop
scripts/test-all.sh --keep-going    # run every component even if one fails, summary at the end
scripts/test-all.sh --with-ci       # also run every GitHub Actions workflow locally via act
scripts/test-all.sh --only backend  # single component: backend|frontend|admin|infra|e2e|smoke|ci
```

Order: `backend` → `frontend` → `admin` → `infra` → (`e2e` if requested) → `smoke` (unless `--no-smoke`) → (`ci` if `--with-ci` or `--only ci`).

### `scripts/smoke.sh` — closed-loop runtime test

Brings up the full docker-compose stack, exercises it end-to-end, scans logs, tears it down. The **non-negotiable** check for every feature PR and every dependency bump.

```bash
scripts/smoke.sh                      # postgres profile, rebuild, teardown on exit
scripts/smoke.sh --provider sqlserver # switch to SqlServer profile
scripts/smoke.sh --keep-up            # leave stack running on success (for inspection)
scripts/smoke.sh --no-build           # skip image rebuild (faster re-runs)
```

What it actually does:

1. Generates `.env` with `POSTGRES_PASSWORD` on first run (mirrors `rebuild.sh`).
2. `docker compose up -d --build` for the selected profile.
3. Waits for the DB container's healthcheck to report healthy, then polls the backend, frontend, and admin HTTP endpoints until they respond (no healthcheck is defined for those — the script polls `/api/health`, `/`, `/` directly).
4. Runs a CRUD round-trip: `GET /api/health` → `POST /api/items/` → `GET /api/items/{pk}` (list) → `GET /api/items/{pk}/{id}` → `PUT` → `DELETE` → `GET` expecting 404.
5. Verifies `frontend` (port 6173) and `admin` (port 6174) serve valid HTML.
6. Scans `docker compose logs` for unhandled exceptions, EF migration failures, panics, `[FATAL]`, etc.
7. Tears down with `docker compose down -v` in a trap (runs even on Ctrl-C).

Exit 0 ⇒ the stack works end-to-end. Exit non-zero ⇒ PR is not done.

### `scripts/ci.sh` — GitHub Actions locally via act

Runs the repo's workflows locally in docker using [`act`](https://github.com/nektos/act). This verifies the **pipeline that runs the code** — catches YAML syntax errors, action version drift, matrix typos, cache-key collisions, and runner-image assumptions that smoke/unit tests can't see.

```bash
scripts/ci.sh                          # safe default subset (excludes build-images.yml)
scripts/ci.sh --event pull_request     # simulate a PR event (default: push)
scripts/ci.sh --list                   # list jobs; don't execute (fast sanity check)
scripts/ci.sh --all                    # include build-images.yml (needs .secrets file)
scripts/ci.sh -- -j <job-name>         # pass args after -- straight through to act
ACT_WORKFLOWS=frontend.yml,admin.yml scripts/ci.sh
```

Requires `act >= 0.2.87` (older versions reject `actions/*` v5+/v6+ which use the node24 runtime). On Apple Silicon, the script auto-appends `--container-architecture linux/amd64` so x86-only action payloads still run.

**Runner image:** `ci.sh` pins `ghcr.io/catthehacker/ubuntu:full-latest` by default (~18 GB, first pull is slow). The smaller `act-latest` image omits `node` from the PATH for post-step execs, which breaks cleanup for every JS-based action (see [nektos/act#107](https://github.com/nektos/act/issues/107)). Override via `ACT_IMAGE=ghcr.io/catthehacker/ubuntu:act-latest scripts/ci.sh` if you're willing to accept the post-step failures for faster downloads.

The default subset **excludes `build-images.yml`** because it pushes to an Azure Container Registry and needs `AZURE_CLIENT_ID` / `AZURE_TENANT_ID` / `AZURE_SUBSCRIPTION_ID` secrets. Run `--all` with a local `.secrets` file (gitignored) if you want to include it.

## Matrix: checks per component

| Component    | Typecheck              | Lint                                       | Unit                        | Integration                        | Build                | Runtime / E2E                      |
| ------------ | ---------------------- | ------------------------------------------ | --------------------------- | ---------------------------------- | -------------------- | ---------------------------------- |
| **backend**  | compiler (C# 13)       | analyzers + `TreatWarningsAsErrors` (enforced during build) | xUnit                       | `WebApplicationFactory<Program>` (`ItemEndpointsTests`, `HealthEndpointTests`) | `dotnet build -c Release`                | via `e2e` + `smoke`                |
| **frontend** | `vue-tsc --noEmit`     | `eslint` (flat config)                     | `vitest` (jsdom)            | —                                  | `vite build`         | via `e2e` + `smoke`                |
| **admin**    | `vue-tsc --noEmit`     | `eslint` (flat config)                     | `vitest` (jsdom)            | —                                  | `vite build`         | via `e2e` + `smoke`                |
| **infra**    | N/A                    | `terraform fmt -check -recursive` + `tflint` | —                           | `terraform init -backend=false && terraform validate` | N/A                  | —                                  |
| **e2e**      | N/A                    | —                                          | —                           | N/A                                | —                    | Playwright (chromium)              |
| **smoke**    | N/A                    | —                                          | —                           | HTTP CRUD against live compose stack | —                    | docker compose full stack          |
| **images**   | N/A                    | —                                          | —                           | —                                  | `docker build --push` (CI only) | —                                  |

## Matrix: where each check runs

| Check                                      | `scripts/test-all.sh` (local) | `scripts/ci.sh` (local act) | GitHub Actions CI |
| ------------------------------------------ | :---------------------------: | :-------------------------: | :---------------: |
| backend `dotnet test`                      |               ✓               |              ✓              |         ✓         |
| backend `dotnet build /warnaserror`        |    ✓ (via `dotnet test`)      |              ✓              |         ✓         |
| frontend typecheck                         |               ✓               |              ✓              |         ✓         |
| frontend lint                              |               ✓               |              ✓              |         ✓         |
| frontend vitest                            |               ✓               |              ✓              |         ✓         |
| frontend build                             |               ✓               |              ✓              |         ✓         |
| admin typecheck                            |               ✓               |              ✓              |         ✓         |
| admin lint                                 |               ✓               |              ✓              |         ✓         |
| admin vitest                               |               ✓               |              ✓              |         ✓         |
| admin build                                |               ✓               |              ✓              |         ✓         |
| infra `terraform fmt`                      |               ✓               |              ✓              |         ✓         |
| infra `terraform validate`                 |               ✓               |              ✓              |         ✓         |
| infra `tflint`                             |     ✓ (if installed)          |              ✓              |         ✓         |
| e2e Playwright                             | opt-in (`--only e2e`)         |              ✓              |         ✓         |
| **smoke** (closed-loop docker compose)     |               ✓               |              —              |         —         |
| build-images (docker build + push)         |              —                | opt-in (`--all` + secrets)  | ✓ (main + manual) |

Two things to note:

- **Smoke runs locally only.** It exercises the live stack with real ports and a real DB. GitHub Actions doesn't currently run it; wiring it in is tracked.
- **`tflint` is soft locally.** If the binary isn't installed, `test-all.sh` skips it with a note so first-time contributors aren't blocked. CI always runs it.

## Commands cheat sheet

| I want to…                                          | Command                                              |
| --------------------------------------------------- | ---------------------------------------------------- |
| Run the full pre-flight gate                        | `scripts/test-all.sh`                                |
| Iterate fast (skip compose loop)                    | `scripts/test-all.sh --no-smoke`                     |
| See every failure, not just the first               | `scripts/test-all.sh --keep-going`                   |
| Run a single component                              | `scripts/test-all.sh --only frontend`                |
| Just the closed-loop runtime test                   | `scripts/smoke.sh`                                   |
| Full local CI rehearsal before pushing              | `scripts/test-all.sh --with-ci`                      |
| Just the GitHub Actions locally                     | `scripts/ci.sh`                                      |
| What would act run? (dry-list)                      | `scripts/ci.sh --list`                               |
| Include `build-images.yml`                          | `scripts/ci.sh --all` (requires `.secrets` file)     |
| Debug one act job                                   | `scripts/ci.sh -- -j check -v`                       |
| Simulate a pull-request event                       | `scripts/ci.sh --event pull_request`                 |
| Leave the stack running after smoke                 | `scripts/smoke.sh --keep-up`                         |
| Switch smoke to SqlServer                           | `scripts/smoke.sh --provider sqlserver`              |

## Extending

Add tests where they go, not where it's convenient:

| When you add…                                       | Put the test in…                                          |
| --------------------------------------------------- | --------------------------------------------------------- |
| A new backend endpoint                              | `backend/tests/ProjectTemplate.Api.Tests/` (xUnit + `WebApplicationFactory<Program>` + `InMemoryWebApplicationFactory` fixture for DB-free runs) |
| A new repository / domain service                   | Same project — direct unit tests on the implementation    |
| A new frontend component                            | `frontend/src/__tests__/` (vitest + `@vue/test-utils`, jsdom environment — use `// @vitest-environment jsdom` directive) |
| A new admin view                                    | `admin/src/__tests__/` (vitest, jsdom; admin doesn't ship `@vue/test-utils` — stick to module-graph / import smoke unless you add the dep) |
| A user-visible flow spanning frontend ↔ backend     | `e2e/tests/*.spec.ts` (Playwright; reads `FRONTEND_URL`, default `http://127.0.0.1:6173`) |
| A new Terraform module                              | `infra/modules/<name>/` with `terraform fmt`-clean code; `tflint` catches most issues |
| A new API route to guarantee at runtime             | Extend `scripts/smoke.sh` CRUD section — the live-stack contract |

The template's contract: **every component has a test surface, not just the backend**. If you add a feature and can't find a home for its test, that's a gap worth raising.

## Troubleshooting

### `POSTGRES_PASSWORD must be set`

`smoke.sh` and `rebuild.sh` both generate `.env` with a random password on first run. If you see this error, either run one of those scripts or create `.env` manually with `POSTGRES_PASSWORD=<anything>`. The file is gitignored; never commit it.

### Port already in use (`6173`, `6174`, `6180`, `6432`)

See `docs/troubleshooting/port-conflicts.md`. Quick fix: `docker compose down -v --remove-orphans` or kill the process holding the port (`lsof -i :6180`).

### `act` complains about `node24` runtime

Upgrade: `brew upgrade act` (need ≥ 0.2.87). `scripts/ci.sh` now fails fast with this message if the installed version is too old. Pinned actions (`actions/checkout@v6`, `actions/setup-dotnet@v5`, `actions/upload-artifact@v7`, `oven-sh/setup-bun@v2`) all use node24.

### `act` says `backend.yml` or `e2e.yml` failed but the tests passed

Known act limitation: `actions/upload-artifact@v7` sends a protobuf field (`mime_type`) that act's internal artifact server doesn't understand, so the upload step fails after 5 retries. The real work (build, test) runs successfully — look for `Passed!` lines in the output. Real GitHub Actions accepts the field without issue; only act is affected.

Verification trick: re-run with the artifact step filtered out —

```bash
scripts/ci.sh -- --job check --no-skip-checkout   # passes act flags through
```

…or just trust the `Passed!` / `Success - Main dotnet test` lines and treat upload-artifact failures as benign. Do **not** pin `upload-artifact` to an older version in the workflow — real CI needs v7's features; this is act's problem, not ours.

### `act` errors with `node: executable file not found in $PATH`

The smaller `catthehacker/ubuntu:act-latest` image doesn't expose `node` to post-step execs, which breaks cleanup for every JS-based action (`upload-artifact`, `setup-bun`, etc.) — see [nektos/act#107](https://github.com/nektos/act/issues/107). `ci.sh` defaults to `ghcr.io/catthehacker/ubuntu:full-latest` to avoid this. First pull is ~18 GB; subsequent runs reuse the cached image.

### act clone of an action times out (transient network)

`act` fetches each `uses:` action's repo on first run (`git clone 'https://github.com/...'`). If you see `i/o timeout` errors, just re-run — successful clones are cached under `~/.cache/act/` and won't be re-fetched.

### `act` on Apple Silicon — slow or fails with platform errors

`scripts/ci.sh` auto-adds `--container-architecture linux/amd64` when it detects `arm64`/`aarch64`. This is required for actions that ship x86-only binaries. Native arm64 is faster but incomplete — keep the amd64 flag unless you know an action is arm64-native.

### Smoke step fails but typecheck/vitest pass

That's the whole point. A green typecheck + unit suite doesn't guarantee the runtime graph (DI, EF migrations, service worker, CORS, Vite proxy, compose network) wires up. Read `docker compose logs` (smoke.sh dumps the last 120 lines on failure) and fix the runtime issue — **do not** paper over it by weakening the log-scan patterns in `smoke.sh`.

### `dotnet` not on PATH

`install/install-dotnet.sh` bootstraps the .NET SDK. If you're contributing from a fresh checkout, run `install/install-deps.sh` which chains the per-stack installers.

### `tflint` reported as skipped locally

Install it: `brew install tflint` (or see `install/install-cli-tools.sh`). Soft-skip is intentional — CI always enforces it, but first-time contributors shouldn't be blocked before they've decided to touch Terraform.
