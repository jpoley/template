import { describe, expect, it } from 'vitest'
import { buildRewriteDest } from '@/middleware'

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
})
