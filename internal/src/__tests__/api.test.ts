import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { del, getJSON, postJSON } from '@/lib/api'

let mockFetch: ReturnType<typeof vi.fn<typeof fetch>>

beforeEach(() => {
  mockFetch = vi.fn<typeof fetch>()
  vi.stubGlobal('fetch', mockFetch)
})

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('api client (browser)', () => {
  it('getJSON prefixes the basePath so Next.js rewrites can proxy', async () => {
    mockFetch.mockResolvedValueOnce(
      new Response(JSON.stringify([{ id: '1' }]), { status: 200 }),
    )
    await getJSON('/api/items/default')
    expect(mockFetch).toHaveBeenCalledTimes(1)
    expect(mockFetch.mock.calls[0]?.[0]).toBe('/internal/api/items/default')
  })

  it('getJSON throws on non-OK with status code', async () => {
    mockFetch.mockResolvedValueOnce(new Response('nope', { status: 500 }))
    await expect(getJSON('/api/items/default')).rejects.toThrow(/HTTP 500/)
  })

  it('postJSON sends JSON with the right headers and parses the response', async () => {
    mockFetch.mockResolvedValueOnce(
      new Response(JSON.stringify({ ok: true }), { status: 201 }),
    )
    const out = await postJSON<{ ok: boolean }>('/api/items', { name: 'x' })
    expect(out).toEqual({ ok: true })
    const init = mockFetch.mock.calls[0]?.[1]
    expect(init?.method).toBe('POST')
    expect((init?.headers as Record<string, string>)['Content-Type']).toBe(
      'application/json',
    )
    expect(init?.body).toBe(JSON.stringify({ name: 'x' }))
  })

  it('del prefixes basePath and preserves pre-encoded path segments verbatim', async () => {
    mockFetch.mockResolvedValueOnce(new Response(null, { status: 204 }))
    const pk = encodeURIComponent('weird/key?with#chars')
    const id = encodeURIComponent('a b/c')
    await del(`/api/items/${pk}/${id}`)
    const calledUrl = mockFetch.mock.calls[0]?.[0]
    expect(calledUrl).toBe(
      '/internal/api/items/weird%2Fkey%3Fwith%23chars/a%20b%2Fc',
    )
  })
})
