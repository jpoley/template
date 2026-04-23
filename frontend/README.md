# Frontend

Vue 3 + TypeScript + Bun + Tailwind 4 + shadcn-vue, PWA/service worker via `vite-plugin-pwa`.

## Scripts

```bash
bun install
bun run dev          # http://localhost:6173
bun run build
bun run preview
bun run test
bun run lint
bun run typecheck
```

## Adding shadcn components

```bash
bunx shadcn-vue@latest add <component>
```

Components land under `src/components/ui/`. The `Button` in `src/components/ui/button/` is the reference example.

## Service worker

The PWA plugin auto-generates `sw.js` and a web manifest in `dist/`. API requests are `NetworkFirst` (5s timeout) so the app stays usable offline for the last-known state. Config lives in `vite.config.ts`.

## Docker

```bash
docker build -t projecttemplate-frontend .
docker run -p 6173:80 projecttemplate-frontend
```

The image is nginx-served static; it does not include the API. Put a reverse proxy (Azure Front Door, nginx, Traefik) in front in production to route `/api/*` to the backend.
