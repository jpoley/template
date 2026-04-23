import { test, expect } from '@playwright/test'

const FRONTEND = process.env.FRONTEND_URL ?? 'http://127.0.0.1:6173'

test.describe('frontend', () => {
  test('home page loads and shows backend health', async ({ page }) => {
    await page.goto(FRONTEND)
    await expect(page.getByRole('heading', { name: 'Welcome' })).toBeVisible()
    await expect(page.getByText('Backend health:')).toBeVisible()
    // The value pulled from /api/health should eventually say "Healthy".
    await expect(page.locator('code')).toHaveText('Healthy', { timeout: 10_000 })
  })

  test('about page is reachable via router link', async ({ page }) => {
    await page.goto(FRONTEND)
    await page.getByRole('link', { name: 'About' }).click()
    await expect(page).toHaveURL(/\/about$/)
    await expect(page.getByRole('heading', { name: 'About' })).toBeVisible()
  })

  test('button click handler fires', async ({ page }) => {
    await page.goto(FRONTEND)
    await page.getByRole('button', { name: 'Click me' }).click()
    await expect(page.locator('code')).toHaveText('clicked')
  })
})
