import { describe, expect, it } from 'vitest'
import { render, screen } from '@testing-library/react'
import '@testing-library/jest-dom/vitest'
import { Providers } from '@/app/providers'
import { Button } from '@/components/ui/button'

describe('internal smoke', () => {
  it('renders Button inside Providers', () => {
    render(
      <Providers>
        <Button>hello</Button>
      </Providers>,
    )
    expect(screen.getByRole('button', { name: 'hello' })).toBeInTheDocument()
  })
})
