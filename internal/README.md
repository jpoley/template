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
bun run dev   # http://localhost:6174
```

Other commands:

```bash
bun run lint        # next lint
bun run typecheck   # tsc --noEmit
bun run test        # vitest (RTL smoke)
bun run build       # next build → .next/standalone/
bun run start       # node .next/standalone/server.js (PORT=6174 default)
```

The Dockerfile is a three-stage build: `deps` (Bun install) → `builder` (Bun
runs `next build`) → `runner` (Node 22 slim, executes `server.js`).
