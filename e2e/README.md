# e2e

Playwright end-to-end browser tests covering the full stack.

Tests boot the backend (`dotnet run`), frontend (`bunx vite`), and internal (`bun run dev` → `next dev`) automatically via Playwright's `webServer` config, then drive real Chromium against them.

## Prerequisites

Installed by `install/install-playwright.sh` (called by `install/bootstrap.sh`):

- `@playwright/test` + Chromium headless shell.
- Chromium runtime `.so` files under `~/.local/lib/playwright-libs/` (no-sudo path).

## Run

```bash
# From the repo root, via the helper that sets LD_LIBRARY_PATH for you:
./e2e/run-playwright.sh test

# If you have sudo and installed system libs directly:
( cd e2e && npx playwright test )
```

If the dev servers are already running, skip the auto-start:

```bash
PLAYWRIGHT_SKIP_SERVERS=1 ./e2e/run-playwright.sh test
```

## Reports and artefacts

- `playwright-report/` — HTML report (opened with `./run-playwright.sh show-report`).
- `test-results/` — traces, videos, screenshots per failing test.
- `screenshots/` — deliberate captures from `tests/screenshots.spec.ts`.

## Conventions

- One spec file per UI surface.
- Locate elements with accessible roles / names (`getByRole`, `getByPlaceholder`) — not CSS selectors unless there's no alternative. It's easier to read and survives refactors.
- Clean up data you create (delete items you added) so tests don't leak state.
- Prefer `toHaveText` / `toHaveCount` with timeouts over `waitForTimeout`.
