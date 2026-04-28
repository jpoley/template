import { test } from '@playwright/test'

const FRONTEND = process.env.FRONTEND_URL ?? 'http://127.0.0.1:6173'
const INTERNAL = process.env.INTERNAL_URL ?? 'http://127.0.0.1:6174'

test('capture: frontend home', async ({ page }) => {
  await page.goto(FRONTEND)
  await page.locator('code', { hasText: 'Healthy' }).waitFor({ timeout: 10_000 })
  await page.screenshot({ path: 'screenshots/frontend-home.png', fullPage: true })
})

test('capture: internal dashboard', async ({ page }) => {
  await page.goto(INTERNAL)
  await page.locator('.font-mono', { hasText: 'Healthy' }).waitFor({ timeout: 10_000 })
  await page.screenshot({ path: 'screenshots/internal-dashboard.png', fullPage: true })
})

test('capture: internal items', async ({ page }) => {
  await page.goto(INTERNAL + '/items')
  await page.getByPlaceholder('new item name').fill('demo-item')
  await page.getByRole('button', { name: 'Add' }).click()
  await page.locator('li', { hasText: 'demo-item' }).waitFor()
  await page.screenshot({ path: 'screenshots/internal-items.png', fullPage: true })
  // cleanup
  await page
    .locator('li', { hasText: 'demo-item' })
    .getByRole('button', { name: 'Delete' })
    .click()
})
