<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { Button } from '@/components/ui/button'

const health = ref<string>('unknown')

onMounted(async () => {
  try {
    const res = await fetch('/api/health')
    health.value = res.ok ? await res.text() : `error ${res.status}`
  } catch (err) {
    health.value = `unreachable: ${(err as Error).message}`
  }
})
</script>

<template>
  <section class="space-y-4">
    <h1 class="text-3xl font-bold">Welcome</h1>
    <p class="text-muted-foreground">
      Backend health: <code>{{ health }}</code>
    </p>
    <Button @click="health = 'clicked'">Click me</Button>
  </section>
</template>
