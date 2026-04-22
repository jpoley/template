<script setup lang="ts">
import { RouterLink, RouterView } from 'vue-router'
</script>

<template>
  <div class="flex min-h-screen bg-background text-foreground">
    <aside class="w-60 border-r p-4 space-y-2">
      <h2 class="text-lg font-bold mb-4">Admin</h2>
      <nav class="flex flex-col gap-1">
        <RouterLink class="hover:underline" to="/">Dashboard</RouterLink>
        <RouterLink class="hover:underline" to="/items">Items</RouterLink>
      </nav>
    </aside>
    <main class="flex-1 p-6">
      <RouterView />
    </main>
  </div>
</template>
