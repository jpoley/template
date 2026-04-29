// @vitest-environment node
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { apiBase } from '@/lib/api'

const ORIGINAL_API_PROXY_TARGET = process.env.API_PROXY_TARGET

describe('apiBase (server-side / RSC path)', () => {
  beforeEach(() => {
    delete process.env.API_PROXY_TARGET
  })

  afterEach(() => {
    if (ORIGINAL_API_PROXY_TARGET === undefined) {
      delete process.env.API_PROXY_TARGET
    } else {
      process.env.API_PROXY_TARGET = ORIGINAL_API_PROXY_TARGET
    }
  })

  it('reads API_PROXY_TARGET when window is undefined', () => {
    process.env.API_PROXY_TARGET = 'https://server-target.example.com'
    expect(apiBase()).toBe('https://server-target.example.com')
  })

  it('falls back to http://backend:8080 when env unset', () => {
    expect(apiBase()).toBe('http://backend:8080')
  })

  it('does NOT return BASE_PATH on the server (no SSR-as-browser foot-gun)', () => {
    // BASE_PATH is the browser-side return; on the server we want a real
    // backend URL so RSC fetches don't loop back through the middleware.
    expect(apiBase()).not.toBe('/internal')
  })
})
