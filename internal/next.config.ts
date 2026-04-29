import type { NextConfig } from 'next'

// One server-only env var drives both the dev-server / standalone-runtime
// rewrite proxy and the RSC fetch base in lib/api.ts. Intentionally NOT a
// NEXT_PUBLIC_* var — exposing the backend URL to the browser bundle would
// invite client-side direct fetches that bypass this proxy and trip CORS.
const apiProxyTarget = process.env.API_PROXY_TARGET || 'http://backend:8080'

const config: NextConfig = {
  output: 'standalone',
  // Hosted under `/internal/*` (Front Door route + Container App ingress).
  // Setting basePath here is what makes the Next.js asset URLs (`_next/static/...`)
  // and `<Link>`-rendered hrefs include the prefix, so they reach this origin
  // instead of falling through to the frontend `/*` route. Local dev runs at
  // http://localhost:6174/internal too, keeping prod and dev topology identical.
  basePath: '/internal',
  async rewrites() {
    // basePath is auto-prefixed onto `source`, so this matches `/internal/api/:path*`.
    // The browser-side fetch base in lib/api.ts mirrors that prefix.
    return [
      {
        source: '/api/:path*',
        destination: `${apiProxyTarget}/api/:path*`,
      },
    ]
  },
}

export default config
