import { test, expect } from '@playwright/test'

// Next.js mounts the app under /internal via basePath.
const INTERNAL = process.env.INTERNAL_URL ?? 'http://127.0.0.1:6174/internal'

test.describe('internal', () => {
  test('dashboard reports healthy backend', async ({ page }) => {
    await page.goto(INTERNAL)
    await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible()
    await expect(page.getByText('Backend')).toBeVisible()
    await expect(page.locator('.font-mono')).toHaveText('Healthy', { timeout: 10_000 })
  })

  test('items CRUD: create, list, delete', async ({ page }) => {
    await page.goto(INTERNAL + '/items')
    await expect(page.getByRole('heading', { name: 'Items' })).toBeVisible()

    const unique = `e2e-item-${Date.now()}`
    await page.getByPlaceholder('new item name').fill(unique)
    await page.getByRole('button', { name: 'Add' }).click()

    // The new item shows up in the list.
    const row = page.locator('li', { hasText: unique })
    await expect(row).toBeVisible({ timeout: 10_000 })

    // Delete it and confirm it disappears.
    await row.getByRole('button', { name: 'Delete' }).click()
    await expect(row).toHaveCount(0, { timeout: 10_000 })
  })

  test('switching partition key re-queries', async ({ page }) => {
    await page.goto(INTERNAL + '/items')

    // Create an item in "default"
    const nameDefault = `default-${Date.now()}`
    await page.getByPlaceholder('new item name').fill(nameDefault)
    await page.getByRole('button', { name: 'Add' }).click()
    await expect(page.locator('li', { hasText: nameDefault })).toBeVisible()

    // Switch partition key — item should disappear from view
    const pkInput = page.getByPlaceholder('partition key')
    await pkInput.fill('other')
    // react-query refetches on reactive dep change; give it a moment
    await expect(page.locator('li', { hasText: nameDefault })).toHaveCount(0, { timeout: 5_000 })

    // Switch back
    await pkInput.fill('default')
    await expect(page.locator('li', { hasText: nameDefault })).toBeVisible({ timeout: 5_000 })

    // cleanup
    await page
      .locator('li', { hasText: nameDefault })
      .getByRole('button', { name: 'Delete' })
      .click()
  })
})
