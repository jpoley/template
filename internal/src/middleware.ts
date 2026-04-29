import { NextResponse, type NextRequest } from 'next/server'

// Runtime-evaluated proxy for `/internal/api/*` → `${API_PROXY_TARGET}/api/*`.
//
// We can't use `rewrites()` in next.config.ts because Next bakes those
// destinations into routes-manifest.json at build time — same image,
// frozen target. Middleware runs on every request, reads `process.env`
// at call time, so Container Apps / compose / playwright can each set
// their own `API_PROXY_TARGET` without rebuilding.
//
// The matcher is written WITHOUT the basePath prefix — Next.js prepends it
// automatically (so `/api/:path*` becomes effectively `/internal/api/:path*`).
// Including `/internal/` in the matcher would cause it to be doubled.
export function middleware(request: NextRequest) {
  const target = process.env.API_PROXY_TARGET || 'http://backend:8080'
  const url = request.nextUrl.clone()
  // request.nextUrl.pathname includes the basePath; strip it so we forward
  // `/api/items/...` (not `/internal/api/items/...`) to the backend.
  const apiPath = url.pathname.replace(/^\/internal\/api\//, '/api/')
  const dest = new URL(apiPath + url.search, target)
  return NextResponse.rewrite(dest)
}

export const config = {
  matcher: '/api/:path*',
}
