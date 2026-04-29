# Internal UI

Internal staff tooling for viewing and editing DB records via the backend API.
Stack: **Next.js 15 (App Router) + React 19 + TypeScript + Tailwind 4 + shadcn (React)**.
Bun handles install/dev; Node 22 is the production runtime (Next.js standalone output).

Server state via `@tanstack/react-query`. Path alias `@/*` → `src/*`.

Not intended for public exposure — `metadata.robots = noindex,nofollow` set on
the root layout. In production, gate with Azure Front Door IP restrictions /
Entra ID auth.

```bash
bun install
# When running natively (not via docker compose), point the proxy at the
# backend on its host port. The middleware reads this at request time.
API_PROXY_TARGET=http://localhost:6180 bun run dev   # http://localhost:6174/internal
```

For convenience, drop the var into `.env.local` (gitignored) so it's picked up
automatically:

```bash
echo 'API_PROXY_TARGET=http://localhost:6180' > .env.local
bun run dev
```

Inside `docker compose up` the env defaults to `http://backend:8080` (the
compose service name) — no override needed there.

The app is mounted under `/internal` via Next.js `basePath` in `next.config.ts`.
This mirrors the production topology (Front Door routes `/internal/*` to this
origin) so dev and prod URLs stay identical — `http://localhost:6174/` is a
404 by design.

Other commands:

```bash
bun run lint        # next lint
bun run typecheck   # tsc --noEmit
bun run test        # vitest (RTL smoke)
bun run build       # next build → .next/standalone/
bun run start       # node .next/standalone/server.js (binds PORT, default 3000)
```

The standalone server reads `PORT` from the environment (defaults to **3000**,
not 6174). To match the dev port locally:

```bash
PORT=6174 bun run start
```

In Docker / Compose / Container Apps the `PORT=3000` env is set explicitly and
the host port is mapped on top (compose maps host `6174` → container `3000`).

The Dockerfile is a three-stage build: `deps` (Bun install) → `builder` (Bun
runs `next build`) → `runner` (Node 22 slim, executes `server.js`).
