import { describe, expect, it } from 'vitest'
import { buildRewriteDest, makeStripRegex } from '@/middleware'

const TARGET = 'http://backend.example.com:8080'

describe('middleware buildRewriteDest', () => {
  it('strips basePath for /internal/api/items/1', () => {
    const dest = buildRewriteDest('/internal/api/items/1', '', TARGET)
    expect(dest.toString()).toBe(`${TARGET}/api/items/1`)
  })

  it('strips basePath for bare /internal/api (no trailing slash)', () => {
    // Regression: previously the strip regex required a trailing slash,
    // so bare /internal/api would forward to ${target}/internal/api.
    const dest = buildRewriteDest('/internal/api', '', TARGET)
    expect(dest.toString()).toBe(`${TARGET}/api`)
  })

  it('preserves trailing slash on /internal/api/', () => {
    const dest = buildRewriteDest('/internal/api/', '', TARGET)
    expect(dest.toString()).toBe(`${TARGET}/api/`)
  })

  it('preserves query string', () => {
    const dest = buildRewriteDest(
      '/internal/api/items',
      '?partition=default&page=2',
      TARGET,
    )
    expect(dest.toString()).toBe(
      `${TARGET}/api/items?partition=default&page=2`,
    )
  })

  it('preserves pre-encoded path segments', () => {
    const dest = buildRewriteDest(
      '/internal/api/items/weird%2Fkey/abc%20123',
      '',
      TARGET,
    )
    expect(dest.toString()).toBe(
      `${TARGET}/api/items/weird%2Fkey/abc%20123`,
    )
  })

  it('honors a different runtime target', () => {
    const dest = buildRewriteDest(
      '/internal/api/health',
      '',
      'https://other-backend.example.com',
    )
    expect(dest.toString()).toBe(
      'https://other-backend.example.com/api/health',
    )
  })

  it('boundary-aware: does NOT strip /internalx (no path boundary)', () => {
    // Defensive: the matcher should never let this reach the helper, but
    // an exported function should be safe in isolation.
    const dest = buildRewriteDest('/internalx/api', '', TARGET)
    expect(dest.toString()).toBe(`${TARGET}/internalx/api`)
  })

  it('treats BASE_PATH as a literal string (regex metacharacters in path)', () => {
    // The strip regex escapes metacharacters in BASE_PATH. A request whose
    // path happens to fit a wildcard interpretation of /internal (e.g.
    // /internAl, where the lowercase "i" is replaced) must NOT match — the
    // strip is literal, not a pattern.
    const dest = buildRewriteDest('/internAl/api', '', TARGET)
    expect(dest.toString()).toBe(`${TARGET}/internAl/api`)
  })
})

// makeStripRegex is exposed so we can exercise the escape behavior across
// basePath values that actually contain metacharacters — the
// /internAl-style test above can't validate escaping because BASE_PATH
// (`/internal`) has no metacharacters in the first place.
describe('makeStripRegex', () => {
  it('strips a literal basePath at a path boundary', () => {
    const re = makeStripRegex('/internal')
    expect('/internal/api/foo'.replace(re, '')).toBe('/api/foo')
    expect('/internalx/api'.replace(re, '')).toBe('/internalx/api')
  })

  it('treats `.` in basePath literally (regression for unescaped metacharacters)', () => {
    const re = makeStripRegex('/api.v1')
    // The literal /api.v1 prefix is stripped:
    expect('/api.v1/items'.replace(re, '')).toBe('/items')
    // But /apiXv1 — which would match `.` if `.` were a wildcard — must not
    // be stripped, since `.` was escaped to a literal dot.
    expect('/apiXv1/items'.replace(re, '')).toBe('/apiXv1/items')
  })

  it('treats `+` in basePath literally', () => {
    const re = makeStripRegex('/internal+x')
    expect('/internal+x/api'.replace(re, '')).toBe('/api')
    // `+` as a regex would mean "one or more of /internal" — must not match.
    expect('/internalinternalx/api'.replace(re, '')).toBe(
      '/internalinternalx/api',
    )
  })
})
