'use client'

import { useQuery } from '@tanstack/react-query'
import { getText } from '@/lib/api'

export default function DashboardPage() {
  const { data: health, isLoading } = useQuery({
    queryKey: ['health'],
    queryFn: () => getText('/api/health'),
    refetchInterval: 10_000,
  })

  return (
    <section className="space-y-4">
      <h1 className="text-3xl font-bold">Dashboard</h1>
      <div className="rounded-lg border p-4">
        <div className="text-sm text-muted-foreground">Backend</div>
        {isLoading ? (
          <div>checking…</div>
        ) : (
          <div className="font-mono">{health}</div>
        )}
      </div>
    </section>
  )
}
