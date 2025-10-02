import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'

const inter = Inter({ subsets: ['latin'] })

export const metadata: Metadata = {
  metadataBase: new URL('https://justspeedit.com'),
  title: {
    default: 'Just Speed It - Free WordPress Performance Audit with Google Lighthouse',
    template: '%s | Just Speed It'
  },
  description: 'Get a free comprehensive WordPress performance audit in 60 seconds. Powered by Google Lighthouse. Analyze Core Web Vitals, SEO, security, and get actionable optimization tips. No signup required.',
  keywords: [
    'WordPress performance audit',
    'Google Lighthouse',
    'Core Web Vitals',
    'WordPress speed test',
    'LCP',
    'CLS',
    'INP',
    'WordPress SEO audit',
    'WordPress security scan',
    'performance optimization',
    'WordPress audit tool',
    'site speed test',
    'PageSpeed insights',
    'WordPress performance',
    'free WordPress audit'
  ],
  authors: [{ name: 'Just Speed It' }],
  creator: 'Just Speed It',
  publisher: 'Just Speed It',
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      'max-video-preview': -1,
      'max-image-preview': 'large',
      'max-snippet': -1,
    },
  },
  openGraph: {
    type: 'website',
    locale: 'en_US',
    url: 'https://justspeedit.com',
    title: 'Just Speed It - Free WordPress Performance Audit Tool',
    description: 'Comprehensive WordPress performance audit powered by Google Lighthouse. Get real Core Web Vitals, screenshots, security analysis, and SEO insights in 60 seconds.',
    siteName: 'Just Speed It',
    images: [
      {
        url: '/og-image.png',
        width: 1200,
        height: 630,
        alt: 'Just Speed It - WordPress Performance Audit',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Just Speed It - Free WordPress Performance Audit',
    description: 'Get a complete WordPress audit with Lighthouse-powered metrics, screenshots, and optimization tips. Free and instant.',
    creator: '@justspeedit',
    images: ['/og-image.png'],
  },
  alternates: {
    canonical: 'https://justspeedit.com',
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
