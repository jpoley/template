import { defineConfig, devices } from '@playwright/test'

const FRONTEND_PORT = 6173
const INTERNAL_PORT = 6174
const BACKEND_PORT = 6180

export default defineConfig({
  testDir: './tests',
  timeout: 30_000,
  expect: { timeout: 5_000 },
  fullyParallel: false,
  workers: 1,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  reporter: process.env.CI ? 'github' : [['list'], ['html', { open: 'never' }]],
  use: {
    actionTimeout: 5_000,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  outputDir: './test-results',

  // Boot the whole stack before tests run. Set PLAYWRIGHT_SKIP_SERVERS=1
  // if the servers are already running (faster inner-loop dev).
  webServer: process.env.PLAYWRIGHT_SKIP_SERVERS
    ? undefined
    : [
        {
          command: `cd ../backend && ASPNETCORE_ENVIRONMENT=Development dotnet run --project src/ProjectTemplate.Api --no-launch-profile --urls http://127.0.0.1:${BACKEND_PORT}`,
          url: `http://127.0.0.1:${BACKEND_PORT}/api/health`,
          reuseExistingServer: true,
          timeout: 120_000,
          stdout: 'ignore',
          stderr: 'pipe',
        },
        {
          command: `cd ../frontend && bunx vite --host 127.0.0.1 --port ${FRONTEND_PORT}`,
          url: `http://127.0.0.1:${FRONTEND_PORT}`,
          reuseExistingServer: true,
          timeout: 60_000,
          stdout: 'ignore',
          stderr: 'pipe',
          env: { VITE_API_URL: `http://127.0.0.1:${BACKEND_PORT}` },
        },
        {
          // The `dev` script in internal/package.json owns the port (single
          // source of truth). We only pass --hostname here so playwright can
          // reach 127.0.0.1 reliably across CI runners.
          command: `cd ../internal && bun run dev -- --hostname 127.0.0.1`,
          // Next.js mounts the app under `/internal` via basePath; probing root
          // would 404.
          url: `http://127.0.0.1:${INTERNAL_PORT}/internal`,
          reuseExistingServer: true,
          timeout: 120_000,
          stdout: 'ignore',
          stderr: 'pipe',
          env: { API_PROXY_TARGET: `http://127.0.0.1:${BACKEND_PORT}` },
        },
      ],
})
