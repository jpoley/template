import type { NextConfig } from 'next'

// One server-only env var drives both the dev-server / standalone-runtime
// rewrite proxy and the RSC fetch base in lib/api.ts. Intentionally NOT a
// NEXT_PUBLIC_* var — exposing the backend URL to the browser bundle would
// invite client-side direct fetches that bypass this proxy and trip CORS.
const apiProxyTarget = process.env.API_PROXY_TARGET || 'http://backend:8080'

const config: NextConfig = {
  output: 'standalone',
  async rewrites() {
    return [
      {
        source: '/api/:path*',
        destination: `${apiProxyTarget}/api/:path*`,
      },
    ]
  },
}

export default config
