import { NextResponse, type NextRequest } from 'next/server'
import { BASE_PATH } from '@/lib/constants'

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

// Escape regex metacharacters so a basePath like `/api.v1` (or anything else
// the centralized constant might become) doesn't change the regex's meaning.
function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

// Exported for tests so the regex behavior can be verified across basePath
// values without mocking the module-level constant.
export function makeStripRegex(basePath: string): RegExp {
  // Boundary-aware: only strip when basePath is a full path segment.
  // `/internalx/api` would otherwise be rewritten to `x/api`.
  return new RegExp(`^${escapeRegExp(basePath)}(?=/|$)`)
}

const STRIP_BASE_PATH = makeStripRegex(BASE_PATH)

// Pure path-rewriting helper, exported for unit tests. Strip just the basePath
// so trailing-slash and no-trailing-slash variants both forward correctly:
//   /internal/api          → /api
//   /internal/api/         → /api/
//   /internal/api/items/1  → /api/items/1
//   /internalx/api         → /internalx/api  (boundary-aware: not stripped)
export function buildRewriteDest(
  pathname: string,
  search: string,
  target: string,
): URL {
  const apiPath = pathname.replace(STRIP_BASE_PATH, '')
  return new URL(apiPath + search, target)
}

export function middleware(request: NextRequest) {
  const target = process.env.API_PROXY_TARGET || 'http://backend:8080'
  const url = request.nextUrl.clone()
  const dest = buildRewriteDest(url.pathname, url.search, target)
  return NextResponse.rewrite(dest)
}

export const config = {
  matcher: '/api/:path*',
}
