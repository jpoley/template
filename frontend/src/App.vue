<script setup lang="ts">
import { RouterLink, RouterView } from 'vue-router'
</script>

<template>
  <div class="min-h-screen bg-background text-foreground">
    <header class="border-b">
      <nav class="container mx-auto flex gap-4 p-4">
        <RouterLink to="/" class="font-semibold">Home</RouterLink>
        <RouterLink to="/about">About</RouterLink>
      </nav>
    </header>
    <main class="container mx-auto p-4">
      <RouterView />
    </main>
  </div>
</template>
