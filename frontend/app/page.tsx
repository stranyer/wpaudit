'use client'

import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { 
  Search, 
  Zap, 
  Shield, 
  Eye, 
  Clock, 
  CheckCircle, 
  ArrowRight,
  Gauge,
  Lock,
  Code,
  TrendingUp,
  Sparkles,
  BarChart3,
  Camera,
  DollarSign,
  Users,
  FileSearch,
  Target
} from 'lucide-react'

export default function Home() {
  const [url, setUrl] = useState('')
  const [isScanning, setIsScanning] = useState(false)

  const normalizeUrl = (inputUrl: string): string => {
    let normalizedUrl = inputUrl.trim()
    
    if (normalizedUrl.includes('@') && !normalizedUrl.startsWith('http')) {
      throw new Error('Please enter a website URL, not an email address')
    }
    
    normalizedUrl = normalizedUrl.replace(/^(https?:\/\/)/, '')
    normalizedUrl = normalizedUrl.replace(/^www\./, '')
    normalizedUrl = normalizedUrl.replace(/\/+$/, '')
    
    if (!normalizedUrl.match(/^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+/)) {
      throw new Error('Please enter a valid website URL (e.g., example.com)')
    }
    
    normalizedUrl = 'https://www.' + normalizedUrl
    
    return normalizedUrl
  }

  const handleScan = async () => {
    if (!url) return
    
    setIsScanning(true)
    
    try {
      const normalizedUrl = normalizeUrl(url)
      console.log('Original URL:', url)
      console.log('Normalized URL:', normalizedUrl)
      
      console.log('Making request to /api/scan')
      const scanResponse = await fetch('/api/scan', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ url: normalizedUrl }),
      })
      
      console.log('Scan response status:', scanResponse.status)
      console.log('Scan response headers:', scanResponse.headers)
      
      if (!scanResponse.ok) {
        const errorText = await scanResponse.text()
        console.error('Scan response error:', errorText)
        throw new Error(`Failed to start scan: ${scanResponse.status} - ${errorText}`)
      }
      
      const scanData = await scanResponse.json()
      console.log('Scan data received:', scanData)
      
      const { jobId } = scanData
      
      if (!jobId) {
        throw new Error('No job ID received from API')
      }
      
      console.log('Job ID:', jobId)
      console.log('Redirecting to scanning page...')
      window.location.href = `/scanning/${jobId}`
      
    } catch (error) {
      console.error('Error starting scan:', error)
      setIsScanning(false)
      alert('Failed to start scan. Please try again.')
    }
  }

  return (
    <div className="min-h-screen bg-gradient-to-b from-white via-gray-50 to-white">
      <header className="border-b border-gray-200 bg-white/80 backdrop-blur-sm sticky top-0 z-50">
        <div className="container mx-auto px-4 py-4">
          <div className="flex items-center justify-between">
            <a href="/" className="flex items-center space-x-2">
              <div className="h-9 w-9 bg-gradient-to-br from-green-400 via-blue-500 to-purple-600 rounded-xl flex items-center justify-center shadow-lg">
                <Zap className="h-5 w-5 text-white" />
              </div>
              <span className="text-xl font-bold bg-gradient-to-r from-gray-900 to-gray-600 bg-clip-text text-transparent">
                Just Speed It
              </span>
            </a>
            <div className="flex items-center space-x-4">
              <a href="/documentation" className="text-gray-600 hover:text-gray-900 transition-colors text-sm font-medium">
                Documentation
              </a>
            </div>
          </div>
        </div>
      </header>

      <main className="container mx-auto px-4 py-16">
        <div className="grid lg:grid-cols-2 gap-12 items-center max-w-7xl mx-auto mb-24">
          <div className="order-2 lg:order-1">
            <div className="mb-6">
              <Badge variant="outline" className="border-green-200 bg-green-50 text-green-700 px-4 py-1.5 text-sm font-medium">
                <Sparkles className="h-3.5 w-3.5 mr-1.5" />
                Powered by Google Lighthouse
              </Badge>
            </div>

            <h1 className="text-5xl md:text-6xl font-extrabold mb-6 tracking-tight leading-tight">
              <span className="bg-gradient-to-r from-gray-900 via-gray-800 to-gray-900 bg-clip-text text-transparent">
                Make your
              </span>
              <br />
              <span className="bg-gradient-to-r from-green-500 via-blue-500 to-purple-600 bg-clip-text text-transparent">
                website faster
              </span>
            </h1>
            
            <p className="text-lg text-gray-600 mb-8 leading-relaxed">
              Get a comprehensive <span className="font-semibold text-gray-900">WordPress performance, SEO, and security audit</span> powered by 
              Google Lighthouse in seconds.
            </p>

            <div className="mb-6">
              <div className="flex gap-3 p-2 bg-white border-2 border-gray-300 rounded-xl shadow-lg hover:shadow-xl transition-shadow">
                <Input
                  type="url"
                  placeholder="Enter your WordPress URL..."
                  value={url}
                  onChange={(e) => setUrl(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && handleScan()}
                  className="flex-1 border-0 bg-transparent text-base focus-visible:ring-0 focus-visible:ring-offset-0 text-gray-900 placeholder:text-gray-400"
                />
                <Button 
                  onClick={handleScan}
                  disabled={!url || isScanning}
                  size="lg"
                  className="px-6 bg-gradient-to-r from-green-500 to-blue-600 hover:from-green-600 hover:to-blue-700 text-white font-semibold rounded-lg shadow-md"
                >
                  {isScanning ? (
                    <>
                      <Clock className="mr-2 h-4 w-4 animate-spin" />
                      Analyzing
                    </>
                  ) : (
                    <>
                      Get Started
                      <ArrowRight className="ml-2 h-4 w-4" />
                    </>
                  )}
                </Button>
              </div>
              <p className="text-sm text-gray-500 mt-3">
                <span className="inline-flex items-center gap-1">
                  <CheckCircle className="h-4 w-4 text-green-500" />
                  Free forever
                </span>
                <span className="mx-2">•</span>
                <span className="inline-flex items-center gap-1">
                  <CheckCircle className="h-4 w-4 text-green-500" />
                  No credit card
                </span>
                <span className="mx-2">•</span>
                <span className="inline-flex items-center gap-1">
                  <CheckCircle className="h-4 w-4 text-green-500" />
                  Results in 60s
                </span>
              </p>
            </div>
          </div>

          <div className="order-1 lg:order-2">
            <div className="relative">
              <div className="absolute inset-0 bg-gradient-to-br from-green-200 via-blue-200 to-purple-200 rounded-3xl blur-3xl opacity-30"></div>
              
              <div className="relative grid grid-cols-2 gap-4">
                <div className="bg-white/90 backdrop-blur-sm p-6 rounded-2xl border border-gray-200 shadow-lg">
                  <div className="text-4xl font-extrabold bg-gradient-to-r from-green-600 to-blue-600 bg-clip-text text-transparent mb-2">
                    20M+
                  </div>
                  <div className="text-sm font-medium text-gray-700">Active Users</div>
                </div>
                <div className="bg-white/90 backdrop-blur-sm p-6 rounded-2xl border border-gray-200 shadow-lg">
                  <div className="text-4xl font-extrabold bg-gradient-to-r from-blue-600 to-purple-600 bg-clip-text text-transparent mb-2">
                    95%
                  </div>
                  <div className="text-sm font-medium text-gray-700">Satisfaction Rate</div>
                </div>
                <div className="col-span-2 bg-white/90 backdrop-blur-sm p-6 rounded-2xl border border-gray-200 shadow-lg">
                  <div className="text-4xl font-extrabold bg-gradient-to-r from-purple-600 to-pink-600 bg-clip-text text-transparent mb-2">
                    5,000+
                  </div>
                  <div className="text-sm font-medium text-gray-700">Sites Optimized Daily</div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div className="mb-24 max-w-6xl mx-auto">
          <div className="text-center mb-12">
            <h2 className="text-4xl md:text-5xl font-bold text-gray-900 mb-4">
              Everything you need in <span className="bg-gradient-to-r from-green-500 to-blue-600 bg-clip-text text-transparent">one place</span>
            </h2>
            <p className="text-lg text-gray-600 max-w-2xl mx-auto">
              Comprehensive analysis powered by industry-leading tools
            </p>
          </div>

          <div className="grid md:grid-cols-2 gap-6">
            <div className="group bg-white rounded-2xl border-2 border-gray-100 p-8 hover:border-green-400 hover:shadow-2xl transition-all duration-300">
              <div className="flex items-start gap-4">
                <div className="flex-shrink-0 h-12 w-12 bg-gradient-to-br from-green-400 to-green-600 rounded-xl flex items-center justify-center shadow-lg group-hover:scale-110 transition-transform">
                  <Gauge className="h-6 w-6 text-white" />
                </div>
                <div>
                  <h3 className="text-xl font-bold text-gray-900 mb-2">Performance</h3>
                  <p className="text-gray-600 leading-relaxed">
                    Lighthouse-powered metrics. LCP, CLS, and INP analysis with actionable insights.
                  </p>
                </div>
              </div>
            </div>

            <div className="group bg-white rounded-2xl border-2 border-gray-100 p-8 hover:border-blue-400 hover:shadow-2xl transition-all duration-300">
              <div className="flex items-start gap-4">
                <div className="flex-shrink-0 h-12 w-12 bg-gradient-to-br from-blue-400 to-blue-600 rounded-xl flex items-center justify-center shadow-lg group-hover:scale-110 transition-transform">
                  <Lock className="h-6 w-6 text-white" />
                </div>
                <div>
                  <h3 className="text-xl font-bold text-gray-900 mb-2">Security</h3>
                  <p className="text-gray-600 leading-relaxed">
                    Detect vulnerabilities, exposed files, and outdated plugins before they become problems.
                  </p>
                </div>
              </div>
            </div>

            <div className="group bg-white rounded-2xl border-2 border-gray-100 p-8 hover:border-purple-400 hover:shadow-2xl transition-all duration-300">
              <div className="flex items-start gap-4">
                <div className="flex-shrink-0 h-12 w-12 bg-gradient-to-br from-purple-400 to-purple-600 rounded-xl flex items-center justify-center shadow-lg group-hover:scale-110 transition-transform">
                  <TrendingUp className="h-6 w-6 text-white" />
                </div>
                <div>
                  <h3 className="text-xl font-bold text-gray-900 mb-2">SEO</h3>
                  <p className="text-gray-600 leading-relaxed">
                    Meta tags, schema markup, and crawlability checks to boost your rankings.
                  </p>
                </div>
              </div>
            </div>

            <div className="group bg-white rounded-2xl border-2 border-gray-100 p-8 hover:border-orange-400 hover:shadow-2xl transition-all duration-300">
              <div className="flex items-start gap-4">
                <div className="flex-shrink-0 h-12 w-12 bg-gradient-to-br from-orange-400 to-orange-600 rounded-xl flex items-center justify-center shadow-lg group-hover:scale-110 transition-transform">
                  <Code className="h-6 w-6 text-white" />
                </div>
                <div>
                  <h3 className="text-xl font-bold text-gray-900 mb-2">WordPress</h3>
                  <p className="text-gray-600 leading-relaxed">
                    Plugin detection, theme analysis, and WP-specific optimization recommendations.
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div className="max-w-6xl mx-auto mb-24">
          <div className="text-center mb-16">
            <h2 className="text-4xl md:text-5xl font-bold text-gray-900 mb-4">
              Follow the <span className="bg-gradient-to-r from-green-500 to-blue-600 bg-clip-text text-transparent">easy steps</span>
            </h2>
            <p className="text-lg text-gray-600 max-w-2xl mx-auto">
              Get comprehensive insights in 3 easy steps - no technical knowledge required
            </p>
          </div>

          <div className="grid md:grid-cols-3 gap-8">
            <div className="relative">
              <div className="bg-white rounded-2xl border-2 border-gray-100 p-8 hover:border-green-400 hover:shadow-2xl transition-all duration-300 h-full">
                <div className="flex items-center gap-3 mb-6">
                  <div className="h-14 w-14 bg-gradient-to-br from-green-400 to-green-600 rounded-full flex items-center justify-center text-white font-bold text-2xl shadow-lg">
                    1
                  </div>
                  <div className="h-12 w-12 bg-green-50 rounded-xl flex items-center justify-center">
                    <Target className="h-6 w-6 text-green-600" />
                  </div>
                </div>
                <h3 className="text-2xl font-bold text-gray-900 mb-3">Enter Your URL</h3>
                <p className="text-gray-600 leading-relaxed">
                  Paste your WordPress site URL and hit analyze. We'll start scanning immediately with no signup required.
                </p>
              </div>
            </div>

            <div className="relative">
              <div className="bg-white rounded-2xl border-2 border-gray-100 p-8 hover:border-blue-400 hover:shadow-2xl transition-all duration-300 h-full">
                <div className="flex items-center gap-3 mb-6">
                  <div className="h-14 w-14 bg-gradient-to-br from-blue-400 to-blue-600 rounded-full flex items-center justify-center text-white font-bold text-2xl shadow-lg">
                    2
                  </div>
                  <div className="h-12 w-12 bg-blue-50 rounded-xl flex items-center justify-center">
                    <Zap className="h-6 w-6 text-blue-600" />
                  </div>
                </div>
                <h3 className="text-2xl font-bold text-gray-900 mb-3">We Analyze</h3>
                <p className="text-gray-600 leading-relaxed">
                  Our AI-powered system runs comprehensive tests on performance, security, SEO, and accessibility in real-time.
                </p>
              </div>
            </div>

            <div className="relative">
              <div className="bg-white rounded-2xl border-2 border-gray-100 p-8 hover:border-purple-400 hover:shadow-2xl transition-all duration-300 h-full">
                <div className="flex items-center gap-3 mb-6">
                  <div className="h-14 w-14 bg-gradient-to-br from-purple-400 to-purple-600 rounded-full flex items-center justify-center text-white font-bold text-2xl shadow-lg">
                    3
                  </div>
                  <div className="h-12 w-12 bg-purple-50 rounded-xl flex items-center justify-center">
                    <CheckCircle className="h-6 w-6 text-purple-600" />
                  </div>
                </div>
                <h3 className="text-2xl font-bold text-gray-900 mb-3">Get Results</h3>
                <p className="text-gray-600 leading-relaxed">
                  Receive a detailed report with actionable recommendations, prioritized by impact on your business goals.
                </p>
              </div>
            </div>
          </div>
        </div>

        <div className="max-w-6xl mx-auto mb-24">
          <div className="text-center mb-12">
            <h2 className="text-4xl md:text-5xl font-bold text-gray-900 mb-4">
              What's in your <span className="bg-gradient-to-r from-green-500 to-blue-600 bg-clip-text text-transparent">audit report</span>
            </h2>
            <p className="text-lg text-gray-600">
              Everything you need to boost performance, fix security issues, and improve SEO
            </p>
          </div>

          <div className="grid md:grid-cols-3 gap-6">
            <div className="bg-white rounded-2xl border-2 border-gray-100 p-6 hover:border-green-400 hover:shadow-xl transition-all">
              <div className="h-12 w-12 bg-green-100 rounded-xl flex items-center justify-center mb-4">
                <Gauge className="h-6 w-6 text-green-600" />
              </div>
              <h3 className="text-lg font-bold text-gray-900 mb-3">Performance Metrics</h3>
              <ul className="space-y-2 text-sm text-gray-600">
                <li className="flex items-center">
                  <CheckCircle className="h-4 w-4 mr-2 text-green-600 flex-shrink-0" />
                  Mobile & Desktop Scores
                </li>
                <li className="flex items-center">
                  <CheckCircle className="h-4 w-4 mr-2 text-green-600 flex-shrink-0" />
                  Core Web Vitals (LCP, CLS, INP)
                </li>
                <li className="flex items-center">
                  <CheckCircle className="h-4 w-4 mr-2 text-green-600 flex-shrink-0" />
                  Loading Times & Metrics
                </li>
              </ul>
            </div>

            <div className="bg-white rounded-2xl border-2 border-gray-100 p-6 hover:border-blue-400 hover:shadow-xl transition-all">
              <div className="h-12 w-12 bg-blue-100 rounded-xl flex items-center justify-center mb-4">
                <Camera className="h-6 w-6 text-blue-600" />
              </div>
              <h3 className="text-lg font-bold text-gray-900 mb-3">Visual Analysis</h3>
              <ul className="space-y-2 text-sm text-gray-600">
                <li className="flex items-center">
                  <CheckCircle className="h-4 w-4 mr-2 text-green-600 flex-shrink-0" />
                  Mobile & Desktop Screenshots
                </li>
                <li className="flex items-center">
                  <CheckCircle className="h-4 w-4 mr-2 text-green-600 flex-shrink-0" />
                  Loading Filmstrip
                </li>
                <li className="flex items-center">
                  <CheckCircle className="h-4 w-4 mr-2 text-green-600 flex-shrink-0" />
                  LCP Element Highlighting
                </li>
              </ul>
            </div>

            <div className="bg-white rounded-2xl border-2 border-gray-100 p-6 hover:border-purple-400 hover:shadow-xl transition-all">
              <div className="h-12 w-12 bg-purple-100 rounded-xl flex items-center justify-center mb-4">
                <TrendingUp className="h-6 w-6 text-purple-600" />
              </div>
              <h3 className="text-lg font-bold text-gray-900 mb-3">Optimization Tips</h3>
              <ul className="space-y-2 text-sm text-gray-600">
                <li className="flex items-center">
                  <CheckCircle className="h-4 w-4 mr-2 text-green-600 flex-shrink-0" />
                  Top 10 Opportunities
                </li>
                <li className="flex items-center">
                  <CheckCircle className="h-4 w-4 mr-2 text-green-600 flex-shrink-0" />
                  Time & Byte Savings
                </li>
                <li className="flex items-center">
                  <CheckCircle className="h-4 w-4 mr-2 text-green-600 flex-shrink-0" />
                  Affected Resources
                </li>
              </ul>
            </div>

            <div className="bg-white rounded-2xl border-2 border-gray-100 p-6 hover:border-red-400 hover:shadow-xl transition-all">
              <div className="h-12 w-12 bg-red-100 rounded-xl flex items-center justify-center mb-4">
                <Shield className="h-6 w-6 text-red-600" />
              </div>
              <h3 className="text-lg font-bold text-gray-900 mb-3">Security Scan</h3>
              <ul className="space-y-2 text-sm text-gray-600">
                <li className="flex items-center">
                  <CheckCircle className="h-4 w-4 mr-2 text-green-600 flex-shrink-0" />
                  SSL/HTTPS Configuration
                </li>
                <li className="flex items-center">
                  <CheckCircle className="h-4 w-4 mr-2 text-green-600 flex-shrink-0" />
                  Security Headers Analysis
                </li>
                <li className="flex items-center">
                  <CheckCircle className="h-4 w-4 mr-2 text-green-600 flex-shrink-0" />
                  Exposed Files Detection
                </li>
              </ul>
            </div>

            <div className="bg-white rounded-2xl border-2 border-gray-100 p-6 hover:border-yellow-400 hover:shadow-xl transition-all">
              <div className="h-12 w-12 bg-yellow-100 rounded-xl flex items-center justify-center mb-4">
                <Eye className="h-6 w-6 text-yellow-600" />
              </div>
              <h3 className="text-lg font-bold text-gray-900 mb-3">SEO Analysis</h3>
              <ul className="space-y-2 text-sm text-gray-600">
                <li className="flex items-center">
                  <CheckCircle className="h-4 w-4 mr-2 text-green-600 flex-shrink-0" />
                  Meta Tags & Schema
                </li>
                <li className="flex items-center">
                  <CheckCircle className="h-4 w-4 mr-2 text-green-600 flex-shrink-0" />
                  Open Graph & Twitter Cards
                </li>
                <li className="flex items-center">
                  <CheckCircle className="h-4 w-4 mr-2 text-green-600 flex-shrink-0" />
                  Robots.txt & Sitemap
                </li>
              </ul>
            </div>

            <div className="bg-white rounded-2xl border-2 border-gray-100 p-6 hover:border-indigo-400 hover:shadow-xl transition-all">
              <div className="h-12 w-12 bg-indigo-100 rounded-xl flex items-center justify-center mb-4">
                <Code className="h-6 w-6 text-indigo-600" />
              </div>
              <h3 className="text-lg font-bold text-gray-900 mb-3">WordPress Specific</h3>
              <ul className="space-y-2 text-sm text-gray-600">
                <li className="flex items-center">
                  <CheckCircle className="h-4 w-4 mr-2 text-green-600 flex-shrink-0" />
                  Plugin & Theme Detection
                </li>
                <li className="flex items-center">
                  <CheckCircle className="h-4 w-4 mr-2 text-green-600 flex-shrink-0" />
                  Version & Security Checks
                </li>
                <li className="flex items-center">
                  <CheckCircle className="h-4 w-4 mr-2 text-green-600 flex-shrink-0" />
                  WP-Specific Optimizations
                </li>
              </ul>
            </div>
          </div>
        </div>

        <div className="max-w-4xl mx-auto bg-gradient-to-br from-green-500 via-blue-600 to-purple-700 rounded-3xl p-12 text-center shadow-2xl relative overflow-hidden">
          <div className="absolute top-0 right-0 w-64 h-64 bg-white/10 rounded-full blur-3xl"></div>
          <div className="absolute bottom-0 left-0 w-64 h-64 bg-white/10 rounded-full blur-3xl"></div>
          
          <div className="relative z-10">
            <Badge variant="outline" className="border-white/30 bg-white/20 text-white px-4 py-1.5 mb-6 font-medium backdrop-blur-sm">
              <Sparkles className="h-3.5 w-3.5 mr-1.5 inline" />
              Start Your Free Audit
            </Badge>
            <h2 className="text-3xl md:text-4xl font-bold text-white mb-4">
              Ready to Speed Up Your WordPress Site?
            </h2>
            <p className="text-lg text-white/90 mb-8 max-w-2xl mx-auto">
              Get your free comprehensive audit report in 60 seconds. No signup, no credit card, completely free forever.
            </p>
            <div className="max-w-lg mx-auto">
              <div className="flex gap-3 p-2.5 bg-white rounded-2xl shadow-2xl">
                <Input
                  type="url"
                  placeholder="Enter your WordPress URL..."
                  value={url}
                  onChange={(e) => setUrl(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && handleScan()}
                  className="flex-1 border-0 focus-visible:ring-0 focus-visible:ring-offset-0 text-base"
                />
                <Button 
                  onClick={handleScan}
                  disabled={!url || isScanning}
                  size="lg"
                  className="px-8 bg-gray-900 hover:bg-black text-white font-semibold rounded-xl shadow-lg"
                >
                  {isScanning ? (
                    <>
                      <Clock className="mr-2 h-4 w-4 animate-spin" />
                      Analyzing
                    </>
                  ) : (
                    <>
                      Analyze Now
                      <ArrowRight className="ml-2 h-4 w-4" />
                    </>
                  )}
                </Button>
              </div>
            </div>
          </div>
        </div>
      </main>

      <footer className="border-t border-gray-200 bg-gradient-to-b from-gray-50 to-white mt-24">
        <div className="container mx-auto px-4 py-12">
          <div className="flex flex-col md:flex-row justify-between items-center">
            <div className="flex items-center space-x-2 mb-6 md:mb-0">
              <div className="h-8 w-8 bg-gradient-to-br from-green-400 via-blue-500 to-purple-600 rounded-lg flex items-center justify-center shadow-md">
                <Zap className="h-5 w-5 text-white" />
              </div>
              <span className="font-bold bg-gradient-to-r from-gray-900 to-gray-600 bg-clip-text text-transparent">
                Just Speed It
              </span>
            </div>
            
            <div className="flex items-center space-x-8 text-sm text-gray-600 mb-6 md:mb-0">
              <a href="/documentation" className="hover:text-gray-900 transition-colors font-medium">Documentation</a>
              <a href="/privacy" className="hover:text-gray-900 transition-colors font-medium">Privacy</a>
              <a href="/terms" className="hover:text-gray-900 transition-colors font-medium">Terms</a>
            </div>
          </div>
          
          <div className="mt-8 pt-8 border-t border-gray-200 text-center text-sm text-gray-500">
            <p>&copy; {new Date().getFullYear()} Just Speed It. Free WordPress Performance Audits Powered by Google Lighthouse.</p>
          </div>
        </div>
      </footer>
    </div>
  )
}
