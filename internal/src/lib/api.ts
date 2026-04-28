export function apiBase(): string {
  if (typeof window === 'undefined') {
    return process.env.API_BASE_INTERNAL || 'http://backend:8080'
  }
  return process.env.NEXT_PUBLIC_API_BASE || ''
}

function url(path: string): string {
  const base = apiBase()
  if (!base) return path
  if (path.startsWith('http')) return path
  return `${base}${path.startsWith('/') ? '' : '/'}${path}`
}

async function ensureOk(res: Response): Promise<Response> {
  if (!res.ok) {
    throw new Error(`HTTP ${res.status} ${res.statusText}`)
  }
  return res
}

export async function getJSON<T>(path: string): Promise<T> {
  const res = await fetch(url(path))
  await ensureOk(res)
  return (await res.json()) as T
}

export async function getText(path: string): Promise<string> {
  const res = await fetch(url(path))
  await ensureOk(res)
  return res.text()
}

export async function postJSON<T>(
  path: string,
  body: unknown,
): Promise<T> {
  const res = await fetch(url(path), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  await ensureOk(res)
  return (await res.json()) as T
}

export async function del(path: string): Promise<void> {
  const res = await fetch(url(path), { method: 'DELETE' })
  await ensureOk(res)
}
