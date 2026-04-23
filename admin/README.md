# Admin UI

Internal UI for viewing and editing DB records via the backend API. Same stack as `frontend/` (Vue 3 + TS + Bun + shadcn-vue), but **no service worker / PWA** — admin is always online, and caching would mask freshness bugs.

Uses `@tanstack/vue-query` for server state (caching, retries, invalidations).

Not intended for public exposure — `meta robots: noindex,nofollow` set in `index.html`. In production, gate with Azure Front Door IP restrictions / Entra ID auth.

```bash
bun install
bun run dev   # http://localhost:6174
```
