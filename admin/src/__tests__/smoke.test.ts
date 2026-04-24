// @vitest-environment jsdom
import { describe, expect, it } from 'vitest'
import App from '@/App.vue'
import { router } from '@/router'

// Admin doesn't ship @vue/test-utils (unlike frontend) — keep this to
// module-graph smoke: ensure App.vue parses, the router is wired, and the
// import chain (vue-router, tailwind plugin, shadcn-vue components) resolves
// cleanly. This catches the breakage pattern library upgrades tend to hit.
describe('admin smoke', () => {
  it('App.vue is a valid component', () => {
    expect(App).toBeTruthy()
    expect(typeof App).toBe('object')
  })

  it('router resolves the configured routes', () => {
    expect(router.resolve('/').name).toBe('dashboard')
    expect(router.resolve('/items').name).toBe('items')
  })
})
