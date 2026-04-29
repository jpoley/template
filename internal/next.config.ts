import type { NextConfig } from 'next'
import { BASE_PATH } from './src/lib/constants'

const config: NextConfig = {
  output: 'standalone',
  // Hosted under `/internal/*` (Front Door route + Container App ingress).
  // Setting basePath here is what makes the Next.js asset URLs (`_next/static/...`)
  // and `<Link>`-rendered hrefs include the prefix, so they reach this origin
  // instead of falling through to the frontend `/*` route. Local dev runs at
  // http://localhost:6174/internal too, keeping prod and dev topology identical.
  basePath: BASE_PATH,
  // The backend proxy intentionally does NOT live in `rewrites()` here:
  // Next.js bakes rewrite destinations into routes-manifest.json at `next build`
  // time, so `process.env.API_PROXY_TARGET` would be frozen to the build-time
  // value. The same image needs to work across deployments (compose, dev,
  // Container Apps), which means the destination must be evaluated at request
  // time. See `src/middleware.ts` for the runtime-evaluated proxy.
}

export default config
