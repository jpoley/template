// @vitest-environment jsdom
import { describe, expect, it } from 'vitest'
import { mount } from '@vue/test-utils'
import App from '@/App.vue'
import { router } from '@/router'

describe('frontend smoke', () => {
  it('App.vue is a valid component', () => {
    expect(App).toBeTruthy()
    expect(typeof App).toBe('object')
  })

  it('router resolves the configured routes', () => {
    const home = router.resolve('/')
    expect(home.name).toBe('home')
    const about = router.resolve('/about')
    expect(about.name).toBe('about')
  })

  it('App mounts with router plugin without throwing', async () => {
    await router.push('/')
    await router.isReady()
    const wrapper = mount(App, { global: { plugins: [router] } })
    expect(wrapper.html()).toContain('Home')
    wrapper.unmount()
  })
})
