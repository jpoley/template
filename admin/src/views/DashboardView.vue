<script setup lang="ts">
import { useQuery } from '@tanstack/vue-query'

const { data: health, isLoading } = useQuery({
  queryKey: ['health'],
  queryFn: async () => {
    const res = await fetch('/api/health')
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    return res.text()
  },
  refetchInterval: 10_000,
})
</script>

<template>
  <section class="space-y-4">
    <h1 class="text-3xl font-bold">Dashboard</h1>
    <div class="rounded-lg border p-4">
      <div class="text-sm text-muted-foreground">Backend</div>
      <div v-if="isLoading">checking…</div>
      <div v-else class="font-mono">{{ health }}</div>
    </div>
  </section>
</template>
