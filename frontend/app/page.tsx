'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { 
  CheckCircle, 
  ArrowRight, 
  Zap, 
  Gauge, 
  Lock, 
  TrendingUp, 
  Code,
  Clock
} from 'lucide-react'
import Link from 'next/link'

export default function Home() {
  const [url, setUrl] = useState('')
  const [isScanning, setIsScanning] = useState(false)
  const router = useRouter()

  const handleScan = async () => {
    if (!url) return

    setIsScanning(true)
    try {
      const response = await fetch('/api/scan', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ url }),
      })

      const data = await response.json()

      if (data.jobId) {
        router.push(`/scanning/${data.jobId}`)
      } else {
        throw new Error('No jobId received')
      }
    } catch (error) {
      console.error('Error starting scan:', error)
      setIsScanning(false)
    }
  }

  return (
    <div className="min-h-screen bg-white overflow-x-hidden">
      
      {/* Header */}
      <header className="sticky top-0 z-50 border-b border-gray-200">
        <nav className="bg-white/80 backdrop-blur-sm">
          <div style={{ height: '80px' }}>
            <div className="container mx-auto px-4 lg:px-8">
              <div className="flex items-center justify-between min-h-[80px]">
                {/* Logo */}
                <div className="flex items-center gap-2">
                  <Link href="/" className="flex items-center gap-2 no-underline">
                    <div className="w-10 h-10 bg-gradient-to-br from-green-400 to-emerald-500 rounded-lg flex items-center justify-center">
                      <Zap className="h-6 w-6 text-white" />
                    </div>
                    <span className="text-xl font-bold text-gray-900">Just Speed It</span>
                  </Link>
                </div>
                
                {/* Nav Right */}
                <div className="flex items-center gap-8">
                  <Link href="/documentation" className="hidden lg:flex text-base text-gray-700 hover:text-gray-900 transition-colors font-medium no-underline">
                    Documentation
                  </Link>
                </div>
              </div>
            </div>
          </div>
        </nav>
      </header>

      {/* Main Content */}
      <div id="wrapper" className="wrap">

        {/* Hero Section */}
        <div id="hero_header" className="relative overflow-hidden">
          {/* Background Image */}
          <div className="absolute top-0 left-0 right-0 h-screen">
            <div className="absolute inset-0 bg-gradient-to-br from-lime-100 via-yellow-100 to-green-100 opacity-80"></div>
          </div>
          
          {/* Gradient Overlays */}
          <div className="absolute top-0 left-0 right-0 h-screen bg-gradient-to-b from-white via-transparent to-white"></div>
          
          {/* Content */}
          <div className="relative z-10 pt-20 lg:pt-24 xl:pt-32">
            <div className="container mx-auto px-4 lg:px-8">
              <div className="flex justify-center">
                <div className="w-full lg:w-10/12">
                  <div className="flex flex-col gap-8 xl:gap-12">
                    
                    {/* Hero Text */}
                    <div className="flex flex-col justify-center items-center gap-4 text-center mx-auto max-w-[650px] lg:max-w-[900px]">
                      <h1 className="text-4xl sm:text-5xl md:text-6xl lg:text-7xl xl:text-8xl font-extrabold tracking-tight leading-none m-0">
                        Speed audit will never be the same again.
                      </h1>
                      <p className="text-lg lg:text-xl xl:text-2xl sm:mt-2 max-w-[550px] text-gray-700">
                        Get a comprehensive <span className="font-semibold text-gray-900">WordPress performance, SEO, and security audit</span> powered by Google Lighthouse in seconds.
                      </p>
                      
                      {/* CTA Form */}
                      <div className="flex flex-col sm:flex-row gap-2 sm:gap-0 bg-white rounded-3xl sm:rounded-2xl shadow-lg p-2 mx-auto mt-4 sm:mt-6 xl:mt-8 w-full max-w-[450px] lg:max-w-[550px]">
                        <Input
                          type="url"
                          placeholder="https://your-wordpress-site.com"
                          value={url}
                          onChange={(e) => setUrl(e.target.value)}
                          onKeyDown={(e) => e.key === 'Enter' && handleScan()}
                          className="flex-1 border-0 bg-transparent text-gray-900 rounded-2xl sm:rounded px-4 py-2 text-base focus-visible:ring-0 focus-visible:ring-offset-0 h-12"
                        />
                        <Button
                          type="submit"
                          onClick={handleScan}
                          disabled={!url || isScanning}
                          className="h-12 bg-gray-900 hover:bg-gray-800 text-white rounded-2xl sm:rounded px-6 py-2 sm:ml-2 lg:min-w-[200px] font-semibold"
                        >
                          {isScanning ? (
                            <>
                              <Clock className="mr-2 h-4 w-4 animate-spin" />
                              Analyzing
                            </>
                          ) : (
                            <>
                              Get Started
                            </>
                          )}
                        </Button>
                      </div>
                      
                      {/* Trust Badges */}
                      <div className="mt-6 sm:mt-12 xl:mt-16">
                        <span className="text-base font-semibold text-gray-900 opacity-80">Powered by Google Lighthouse</span>
                        <div className="flex items-center justify-center gap-4 mt-4 text-sm text-gray-600">
                          <span className="flex items-center gap-1.5">
                            <CheckCircle className="h-4 w-4 text-green-600" />
                            <span className="font-medium">Free forever</span>
                          </span>
                          <span className="flex items-center gap-1.5">
                            <CheckCircle className="h-4 w-4 text-green-600" />
                            <span className="font-medium">No credit card</span>
                          </span>
                          <span className="flex items-center gap-1.5">
                            <CheckCircle className="h-4 w-4 text-green-600" />
                            <span className="font-medium">Results in 60s</span>
                          </span>
                        </div>
                      </div>
                    </div>
                    
                    {/* Hero Image */}
                    <div className="rounded-2xl mx-auto max-w-[1000px] mb-6 sm:mb-8 md:mb-12 xl:mb-16 overflow-hidden border border-gray-200 shadow-md lg:shadow-xl">
                      <div className="w-full aspect-[12/7] bg-gradient-to-br from-emerald-50 via-lime-50 to-green-100 flex items-center justify-center">
                        <div className="text-center px-4">
                          <Gauge className="h-24 w-24 text-emerald-600 mx-auto mb-4 opacity-20" />
                          <p className="text-lg font-semibold text-gray-500">Dashboard Preview</p>
                        </div>
                      </div>
                    </div>
                    
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Key Features Section */}
        <div id="key_features" className="overflow-hidden">
          <div className="py-12 sm:py-16 xl:py-20">
            <div className="container mx-auto px-4 lg:px-8 max-w-6xl">
              <div className="max-w-[750px] xl:max-w-[900px] mx-auto">
                
                {/* Section Heading */}
                <div className="flex flex-col items-center gap-4 xl:gap-6 mb-12 sm:mb-16 xl:mb-20 max-w-[500px] xl:max-w-[600px] mx-auto text-center">
                  <span className="text-xs font-bold py-1 px-3 border border-gray-300 rounded uppercase bg-gradient-to-r from-green-600 to-blue-600 bg-clip-text text-transparent">
                    Key features
                  </span>
                  <h2 className="text-3xl sm:text-4xl xl:text-5xl font-extrabold m-0 leading-tight">
                    Powered by Google Lighthouse
                  </h2>
                </div>
                
                {/* Features Grid */}
                <div className="grid grid-cols-1 gap-4 sm:gap-6">
                  
                  {/* Feature 1 - 2 columns */}
                  <div>
                    <div className="relative overflow-hidden rounded-2xl sm:rounded-3xl xl:rounded-[32px] border border-gray-200">
                      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                        <div>
                          <div className="flex flex-col gap-6 justify-between p-4 sm:p-6 xl:p-8 z-10 relative">
                            <div className="flex flex-col gap-2 sm:gap-4">
                              <h4 className="text-2xl xl:text-3xl font-bold m-0">Core Web Vitals</h4>
                              <p className="text-sm xl:text-base text-gray-600">
                                Get real LCP, CLS, FID scores. See exactly what's slowing down your WordPress site.
                              </p>
                            </div>
                            <Link href="/documentation" className="inline-flex items-center gap-2 text-sm font-bold text-transparent bg-gradient-to-r from-green-600 to-blue-600 bg-clip-text no-underline hover:gap-3 transition-all">
                              <span>Learn more</span>
                              <ArrowRight className="h-4 w-4 text-green-600" />
                            </Link>
                          </div>
                        </div>
                        <div>
                          <div className="relative aspect-square overflow-hidden h-full bg-gradient-to-br from-emerald-50 to-green-50 flex items-center justify-center">
                            <Gauge className="h-32 w-32 text-emerald-600" />
                          </div>
                        </div>
                      </div>
                      {/* Gradient Overlay */}
                      <div className="absolute top-0 left-0 w-1/2 h-full bg-gradient-to-r from-gray-50 to-transparent z-0 hidden sm:block"></div>
                      <div className="absolute top-0 left-0 w-full h-1/2 bg-gradient-to-b from-gray-50 to-transparent z-0 sm:hidden"></div>
                    </div>
                  </div>

                  {/* Feature 2 - 2 columns */}
                  <div className="sm:grid sm:grid-cols-2 gap-4">
                    <div>
                      <div className="relative overflow-hidden rounded-2xl sm:rounded-3xl xl:rounded-[32px] border border-gray-200">
                        <div className="grid grid-cols-1 gap-4">
                          <div className="order-2 sm:order-1">
                            <div className="relative h-[450px] bg-gradient-to-br from-blue-50 to-cyan-50 flex items-center justify-center">
                              <Lock className="h-32 w-32 text-blue-600" />
                            </div>
                          </div>
                          <div className="order-1 sm:order-2">
                            <div className="flex flex-col gap-6 justify-between p-4 sm:p-6 xl:p-8 z-10 relative">
                              <div className="flex flex-col gap-2 sm:gap-4">
                                <h4 className="text-2xl xl:text-3xl font-bold m-0">Security Scan</h4>
                                <p className="text-sm xl:text-base text-gray-600">
                                  Find exposed wp-config.php, vulnerable plugins, and outdated WordPress versions.
                                </p>
                              </div>
                            </div>
                          </div>
                        </div>
                        {/* Gradient Overlay */}
                        <div className="absolute bottom-0 right-0 w-full h-1/2 bg-gradient-to-t from-gray-50 to-transparent z-0 hidden sm:block"></div>
                        <div className="absolute top-0 left-0 w-full h-1/2 bg-gradient-to-b from-gray-50 to-transparent z-0 sm:hidden"></div>
                      </div>
                    </div>
                    
                    <div>
                      <div className="relative overflow-hidden rounded-2xl sm:rounded-3xl xl:rounded-[32px] border border-gray-200">
                        <div className="grid grid-cols-1 gap-4">
                          <div>
                            <div className="flex flex-col gap-6 justify-between p-4 sm:p-6 xl:p-8 z-10 relative">
                              <div className="flex flex-col gap-2 sm:gap-4">
                                <h4 className="text-2xl xl:text-3xl font-bold m-0">SEO Analysis</h4>
                                <p className="text-sm xl:text-base text-gray-600">
                                  Check meta tags, Open Graph, Twitter Cards, and schema.org structured data.
                                </p>
                              </div>
                            </div>
                          </div>
                          <div>
                            <div className="relative h-[450px] bg-gradient-to-br from-purple-50 to-pink-50 flex items-center justify-center">
                              <TrendingUp className="h-32 w-32 text-purple-600" />
                            </div>
                          </div>
                        </div>
                        {/* Gradient Overlay */}
                        <div className="absolute top-0 left-0 w-full h-1/2 bg-gradient-to-b from-gray-50 to-transparent z-0"></div>
                      </div>
                    </div>
                  </div>

                  {/* Feature 4 - Full width */}
                  <div>
                    <div className="relative overflow-hidden rounded-2xl sm:rounded-3xl xl:rounded-[32px] border border-gray-200">
                      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                        <div className="order-2 sm:order-1">
                          <div className="relative aspect-square overflow-hidden h-full bg-gradient-to-br from-orange-50 to-amber-50 flex items-center justify-center">
                            <Code className="h-32 w-32 text-orange-600" />
                          </div>
                        </div>
                        <div className="order-1 sm:order-2">
                          <div className="flex flex-col gap-6 justify-between p-4 sm:p-6 xl:p-8 z-10 relative">
                            <div className="flex flex-col gap-2 sm:gap-4">
                              <h4 className="text-2xl xl:text-3xl font-bold m-0">WordPress Deep Dive</h4>
                              <p className="text-sm xl:text-base text-gray-600">
                                Identify active plugins, detect your theme, and get WP-specific speed recommendations.
                              </p>
                            </div>
                            <Link href="/documentation" className="inline-flex items-center gap-2 text-sm font-bold text-transparent bg-gradient-to-r from-green-600 to-blue-600 bg-clip-text no-underline hover:gap-3 transition-all">
                              <span>See features in action</span>
                              <ArrowRight className="h-4 w-4 text-green-600" />
                            </Link>
                          </div>
                        </div>
                      </div>
                      {/* Gradient Overlay */}
                      <div className="absolute top-0 right-0 w-3/4 h-full bg-gradient-to-l from-gray-50 to-transparent z-0 hidden sm:block"></div>
                      <div className="absolute top-0 left-0 w-full h-1/2 bg-gradient-to-b from-gray-50 to-transparent z-0 sm:hidden"></div>
                    </div>
                  </div>

                </div>
                
                {/* CTA Button */}
                <div className="flex flex-col items-center mt-12 sm:mt-16 xl:mt-20">
                  <Button 
                    onClick={() => document.getElementById('hero_header')?.scrollIntoView({ behavior: 'smooth' })}
                    className="h-12 lg:h-14 bg-gray-900 hover:bg-gray-800 text-white rounded-2xl px-6 py-4 lg:min-w-[200px] font-semibold"
                  >
                    Start Auditing Now
                  </Button>
                </div>
              </div>
            </div>
          </div>
        </div>

      </div>

      {/* Footer */}
      <footer className="bg-gray-900 text-gray-300 py-16">
        <div className="container mx-auto px-4 lg:px-8">
          <div className="max-w-6xl mx-auto">
            <div className="grid md:grid-cols-4 gap-12">
              
              {/* Brand Column */}
              <div className="md:col-span-2">
                <Link href="/" className="flex items-center gap-2 mb-6 no-underline">
                  <div className="w-10 h-10 bg-gradient-to-br from-green-400 to-emerald-500 rounded-lg flex items-center justify-center">
                    <Zap className="h-6 w-6 text-white" />
                  </div>
                  <span className="text-xl font-bold text-white">
                    Just Speed It
                  </span>
                </Link>
                <p className="text-base text-gray-400 leading-relaxed">
                  Comprehensive WordPress performance, SEO, and security audits powered by Google Lighthouse.
                </p>
              </div>

              {/* Links Column */}
              <div>
                <h4 className="font-bold text-white mb-4 text-base">Product</h4>
                <ul className="space-y-3 text-base list-none p-0 m-0">
                  <li><Link href="/documentation" className="hover:text-white transition-colors no-underline text-gray-300">Documentation</Link></li>
                </ul>
              </div>

              {/* Legal Column */}
              <div>
                <h4 className="font-bold text-white mb-4 text-base">Legal</h4>
                <ul className="space-y-3 text-base list-none p-0 m-0">
                  <li><Link href="/privacy" className="hover:text-white transition-colors no-underline text-gray-300">Privacy Policy</Link></li>
                  <li><Link href="/terms" className="hover:text-white transition-colors no-underline text-gray-300">Terms of Service</Link></li>
                </ul>
              </div>

            </div>

            <div className="border-t border-gray-800 mt-12 pt-8 text-center text-sm text-gray-500">
              <p className="m-0">&copy; 2025 Just Speed It. All rights reserved.</p>
            </div>
          </div>
        </div>
      </footer>

    </div>
  )
}
