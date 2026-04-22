<script setup lang="ts">
import { ref } from 'vue'
import { useQuery, useMutation, useQueryClient } from '@tanstack/vue-query'
import { Button } from '@/components/ui/button'
import type { Item } from '@/lib/types'

const partitionKey = ref('default')
const newName = ref('')
const client = useQueryClient()

const { data: items, isLoading } = useQuery({
  queryKey: ['items', partitionKey] as const,
  queryFn: async () => {
    const res = await fetch(`/api/items/${partitionKey.value}`)
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    return (await res.json()) as Item[]
  },
})

const create = useMutation({
  mutationFn: async (name: string) => {
    const res = await fetch('/api/items', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ partitionKey: partitionKey.value, name }),
    })
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    return res.json()
  },
  onSuccess: () => {
    newName.value = ''
    client.invalidateQueries({ queryKey: ['items'] })
  },
})

const remove = useMutation({
  mutationFn: async (item: Item) => {
    const res = await fetch(`/api/items/${item.partitionKey}/${item.id}`, { method: 'DELETE' })
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
  },
  onSuccess: () => client.invalidateQueries({ queryKey: ['items'] }),
})
</script>

<template>
  <section class="space-y-4">
    <h1 class="text-3xl font-bold">Items</h1>

    <div class="flex gap-2">
      <input
        v-model="partitionKey"
        class="border rounded px-2 py-1"
        placeholder="partition key"
      />
    </div>

    <form class="flex gap-2" @submit.prevent="create.mutate(newName)">
      <input
        v-model="newName"
        required
        class="flex-1 border rounded px-2 py-1"
        placeholder="new item name"
      />
      <Button type="submit" :disabled="create.isPending.value">Add</Button>
    </form>

    <div v-if="isLoading">loading…</div>
    <ul v-else class="divide-y rounded-lg border">
      <li
        v-for="item in items"
        :key="item.id"
        class="flex items-center justify-between p-3"
      >
        <div>
          <div class="font-medium">{{ item.name }}</div>
          <div class="text-xs text-muted-foreground font-mono">{{ item.id }}</div>
        </div>
        <Button variant="destructive" size="sm" @click="remove.mutate(item)">
          Delete
        </Button>
      </li>
    </ul>
  </section>
</template>
