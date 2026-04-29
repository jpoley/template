'use client'

import { useState, type FormEvent } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Button } from '@/components/ui/button'
import { del, getJSON, postJSON } from '@/lib/api'
import type { Item } from '@/lib/types'

export default function ItemsPage() {
  const [partitionKey, setPartitionKey] = useState('default')
  const [newName, setNewName] = useState('')
  const client = useQueryClient()

  const { data: items, isLoading } = useQuery({
    queryKey: ['items', partitionKey] as const,
    queryFn: () =>
      getJSON<Item[]>(`/api/items/${encodeURIComponent(partitionKey)}`),
  })

  const create = useMutation({
    mutationFn: (name: string) =>
      postJSON<Item>('/api/items', { partitionKey, name }),
    onSuccess: () => {
      setNewName('')
      client.invalidateQueries({ queryKey: ['items'] })
    },
  })

  const remove = useMutation({
    mutationFn: (item: Item) =>
      del(
        `/api/items/${encodeURIComponent(item.partitionKey)}/${encodeURIComponent(item.id)}`,
      ),
    onSuccess: () => client.invalidateQueries({ queryKey: ['items'] }),
  })

  const onSubmit = (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault()
    if (!newName) return
    create.mutate(newName)
  }

  return (
    <section className="space-y-4">
      <h1 className="text-3xl font-bold">Items</h1>

      <div className="flex gap-2">
        <input
          value={partitionKey}
          onChange={(e) => setPartitionKey(e.target.value)}
          className="border rounded px-2 py-1"
          placeholder="partition key"
        />
      </div>

      <form className="flex gap-2" onSubmit={onSubmit}>
        <input
          value={newName}
          onChange={(e) => setNewName(e.target.value)}
          required
          className="flex-1 border rounded px-2 py-1"
          placeholder="new item name"
        />
        <Button type="submit" disabled={create.isPending}>
          Add
        </Button>
      </form>

      {isLoading ? (
        <div>loading…</div>
      ) : (
        <ul className="divide-y rounded-lg border">
          {items?.map((item) => (
            <li
              key={item.id}
              className="flex items-center justify-between p-3"
            >
              <div>
                <div className="font-medium">{item.name}</div>
                <div className="text-xs text-muted-foreground font-mono">
                  {item.id}
                </div>
              </div>
              <Button
                variant="destructive"
                size="sm"
                onClick={() => remove.mutate(item)}
              >
                Delete
              </Button>
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}
