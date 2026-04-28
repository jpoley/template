import type { Metadata } from 'next'
import Link from 'next/link'
import type { ReactNode } from 'react'
import './globals.css'
import { Providers } from './providers'

export const metadata: Metadata = {
  title: 'Internal · Project Template',
  robots: { index: false, follow: false },
}

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Providers>
          <div className="flex min-h-screen bg-background text-foreground">
            <aside className="w-60 border-r p-4 space-y-2">
              <h2 className="text-lg font-bold mb-4">Internal</h2>
              <nav className="flex flex-col gap-1">
                <Link className="hover:underline" href="/">
                  Dashboard
                </Link>
                <Link className="hover:underline" href="/items">
                  Items
                </Link>
              </nav>
            </aside>
            <main className="flex-1 p-6">{children}</main>
          </div>
        </Providers>
      </body>
    </html>
  )
}
