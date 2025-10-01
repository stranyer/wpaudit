import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'

const inter = Inter({ subsets: ['latin'] })

export const metadata: Metadata = {
  title: 'Just Audit It - WordPress Performance & Security Audit',
  description: 'Audit your WordPress site. Fix what actually slows you down. A PageSpeed score won\'t pay your bills. Faster sites do.',
  openGraph: {
    title: 'Just Audit It - WordPress Performance & Security Audit',
    description: 'Free WordPress performance, SEO, and security audit powered by Google Lighthouse',
    type: 'website',
    locale: 'en_US',
    siteName: 'Just Audit It',
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Just Audit It - WordPress Performance & Security Audit',
    description: 'Free WordPress performance, SEO, and security audit powered by Google Lighthouse',
  },
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <body className={inter.className}>{children}</body>
    </html>
  )
}
