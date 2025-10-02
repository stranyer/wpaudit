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
    
    // Validate it's not an email address
    if (normalizedUrl.includes('@') && !normalizedUrl.startsWith('http')) {
      throw new Error('Please enter a website URL, not an email address')
    }
    
    // Remove any protocol first to clean the input
    normalizedUrl = normalizedUrl.replace(/^(https?:\/\/)/, '')
    
    // Remove www. temporarily to avoid duplication
    normalizedUrl = normalizedUrl.replace(/^www\./, '')
    
    // Remove trailing slashes
    normalizedUrl = normalizedUrl.replace(/\/+$/, '')
    
    // Validate basic URL structure (domain.tld)
    if (!normalizedUrl.match(/^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+/)) {
      throw new Error('Please enter a valid website URL (e.g., example.com)')
    }
    
    // Add https and www
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
      // Start scan
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
      
      // Redirect to scanning page
      console.log('Redirecting to scanning page...')
      window.location.href = `/scanning/${jobId}`
      
    } catch (error) {
      console.error('Error starting scan:', error)
      setIsScanning(false)
      alert('Failed to start scan. Please try again.')
    }
  }

  return (
    <div className="min-h-screen bg-white">
      {/* Header */}
      <header className="border-b border-gray-200 bg-white sticky top-0 z-50">
        <div className="container mx-auto px-4 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center space-x-2">
              <div className="h-8 w-8 bg-black rounded-md flex items-center justify-center">
                <Zap className="h-5 w-5 text-white" />
              </div>
              <span className="text-xl font-semibold text-gray-900">Just Speed It</span>
            </div>
            <div className="flex items-center space-x-4">
              <Button variant="ghost" size="sm" className="text-gray-600">
                Documentation
              </Button>
              <Button variant="outline" size="sm" className="border-gray-200">
                Sign In
              </Button>
            </div>
          </div>
        </div>
      </header>

      {/* Hero Section */}
      <main className="container mx-auto px-4 py-20">
        <div className="max-w-5xl mx-auto">
          {/* Badge */}
          <div className="flex justify-center mb-6">
            <Badge variant="outline" className="border-gray-200 text-gray-600 px-3 py-1">
              <Sparkles className="h-3 w-3 mr-1" />
              Powered by Google Lighthouse
            </Badge>
          </div>

          {/* Main Heading */}
          <h1 className="text-6xl md:text-7xl font-bold text-center text-gray-900 mb-6 tracking-tight">
            Slow WordPress?
            <br />
            <span className="text-gray-400">We'll Show You Why.</span>
          </h1>
          
          <p className="text-xl text-center text-gray-600 mb-12 max-w-2xl mx-auto">
            Get a comprehensive performance, SEO, and security audit powered by Google Lighthouse. 
            <span className="font-medium text-gray-900"> See exactly what's slowing you down and how to fix it.</span>
          </p>

          {/* URL Input */}
          <div className="max-w-2xl mx-auto mb-16">
            <div className="flex gap-3 p-2 bg-gray-50 border border-gray-200 rounded-lg shadow-sm">
              <Input
                type="url"
                placeholder="Enter your WordPress URL..."
                value={url}
                onChange={(e) => setUrl(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && handleScan()}
                className="flex-1 border-0 bg-transparent text-base focus-visible:ring-0 focus-visible:ring-offset-0"
              />
              <Button 
                onClick={handleScan}
                disabled={!url || isScanning}
                size="lg"
                className="px-6 bg-black hover:bg-gray-800 text-white"
              >
                {isScanning ? (
                  <>
                    <Clock className="mr-2 h-4 w-4 animate-spin" />
                    Analyzing
                  </>
                ) : (
                  <>
                    Analyze Site
                    <ArrowRight className="ml-2 h-4 w-4" />
                  </>
                )}
              </Button>
            </div>
            <p className="text-sm text-gray-500 mt-3 text-center">
              Free forever. No credit card. Results in 60-90 seconds.
            </p>
          </div>

          {/* Stats / Trust Elements */}
          <div className="grid grid-cols-3 gap-8 max-w-3xl mx-auto mb-20 py-8 border-y border-gray-100">
            <div className="text-center">
              <div className="text-3xl font-bold text-gray-900 mb-1">10,000+</div>
              <div className="text-sm text-gray-600">Sites Audited</div>
            </div>
            <div className="text-center border-x border-gray-100">
              <div className="text-3xl font-bold text-gray-900 mb-1">60s</div>
              <div className="text-sm text-gray-600">Average Scan Time</div>
            </div>
            <div className="text-center">
              <div className="text-3xl font-bold text-gray-900 mb-1">100%</div>
              <div className="text-sm text-gray-600">Free & Open</div>
            </div>
          </div>

          {/* Features Grid */}
          <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-6 mb-20">
            <Card className="border-gray-200 hover:shadow-md transition-shadow">
              <CardHeader>
                <div className="h-12 w-12 bg-gray-100 rounded-lg flex items-center justify-center mb-4">
                  <Gauge className="h-6 w-6 text-gray-900" />
                </div>
                <CardTitle className="text-lg text-gray-900">Performance</CardTitle>
                <CardDescription className="text-gray-600">
                  Lighthouse-powered metrics. LCP, CLS, and INP analysis.
                </CardDescription>
              </CardHeader>
            </Card>

            <Card className="border-gray-200 hover:shadow-md transition-shadow">
              <CardHeader>
                <div className="h-12 w-12 bg-gray-100 rounded-lg flex items-center justify-center mb-4">
                  <Lock className="h-6 w-6 text-gray-900" />
                </div>
                <CardTitle className="text-lg text-gray-900">Security</CardTitle>
                <CardDescription className="text-gray-600">
                  Detect vulnerabilities, exposed files, and outdated plugins.
                </CardDescription>
              </CardHeader>
            </Card>

            <Card className="border-gray-200 hover:shadow-md transition-shadow">
              <CardHeader>
                <div className="h-12 w-12 bg-gray-100 rounded-lg flex items-center justify-center mb-4">
                  <TrendingUp className="h-6 w-6 text-gray-900" />
                </div>
                <CardTitle className="text-lg text-gray-900">SEO</CardTitle>
                <CardDescription className="text-gray-600">
                  Meta tags, schema markup, and crawlability checks.
                </CardDescription>
              </CardHeader>
            </Card>

            <Card className="border-gray-200 hover:shadow-md transition-shadow">
              <CardHeader>
                <div className="h-12 w-12 bg-gray-100 rounded-lg flex items-center justify-center mb-4">
                  <Code className="h-6 w-6 text-gray-900" />
                </div>
                <CardTitle className="text-lg text-gray-900">WordPress</CardTitle>
                <CardDescription className="text-gray-600">
                  Plugin detection, theme analysis, and WP-specific issues.
                </CardDescription>
              </CardHeader>
            </Card>
          </div>

          {/* How It Works */}
          <div className="max-w-5xl mx-auto mb-24">
            <div className="text-center mb-16">
              <Badge variant="outline" className="border-gray-200 text-gray-600 px-3 py-1 mb-4">
                Simple Process
              </Badge>
              <h2 className="text-4xl font-bold text-gray-900 mb-4">
                How It Works
              </h2>
              <p className="text-lg text-gray-600">
                Get comprehensive insights in 3 easy steps
              </p>
            </div>

            <div className="grid md:grid-cols-3 gap-8">
              {/* Step 1 */}
              <div className="relative">
                <div className="absolute -top-4 -left-4 h-12 w-12 bg-black rounded-full flex items-center justify-center text-white font-bold text-xl z-10">
                  1
                </div>
                <Card className="border-2 border-gray-200 h-full pt-8">
                  <CardHeader>
                    <div className="h-14 w-14 bg-gray-100 rounded-lg flex items-center justify-center mb-4">
                      <Target className="h-7 w-7 text-gray-900" />
                    </div>
                    <CardTitle className="text-xl text-gray-900 mb-2">Enter Your URL</CardTitle>
                    <CardDescription className="text-gray-600 text-base">
                      Paste your WordPress site URL and hit analyze. We'll start scanning immediately.
                    </CardDescription>
                  </CardHeader>
                </Card>
              </div>

              {/* Step 2 */}
              <div className="relative">
                <div className="absolute -top-4 -left-4 h-12 w-12 bg-black rounded-full flex items-center justify-center text-white font-bold text-xl z-10">
                  2
                </div>
                <Card className="border-2 border-gray-200 h-full pt-8">
                  <CardHeader>
                    <div className="h-14 w-14 bg-gray-100 rounded-lg flex items-center justify-center mb-4">
                      <FileSearch className="h-7 w-7 text-gray-900" />
                    </div>
                    <CardTitle className="text-xl text-gray-900 mb-2">We Analyze Everything</CardTitle>
                    <CardDescription className="text-gray-600 text-base">
                      Our system runs Lighthouse tests, security scans, and SEO checks in parallel. Takes 60-90 seconds.
                    </CardDescription>
                  </CardHeader>
                </Card>
              </div>

              {/* Step 3 */}
              <div className="relative">
                <div className="absolute -top-4 -left-4 h-12 w-12 bg-black rounded-full flex items-center justify-center text-white font-bold text-xl z-10">
                  3
                </div>
                <Card className="border-2 border-gray-200 h-full pt-8">
                  <CardHeader>
                    <div className="h-14 w-14 bg-gray-100 rounded-lg flex items-center justify-center mb-4">
                      <BarChart3 className="h-7 w-7 text-gray-900" />
                    </div>
                    <CardTitle className="text-xl text-gray-900 mb-2">Get Your Report</CardTitle>
                    <CardDescription className="text-gray-600 text-base">
                      Receive a detailed report with scores, screenshots, and actionable recommendations to improve.
                    </CardDescription>
                  </CardHeader>
                </Card>
              </div>
            </div>
          </div>

          {/* What You Get Section */}
          <div className="max-w-5xl mx-auto mb-24">
            <div className="text-center mb-12">
              <h2 className="text-3xl font-bold text-gray-900 mb-4">
                What's in Your Audit Report
              </h2>
              <p className="text-gray-600">
                Everything you need to boost performance, fix security issues, and improve SEO
              </p>
            </div>

            <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6">
              {/* Performance */}
              <Card className="border-gray-200 hover:shadow-md transition-shadow">
                <CardHeader>
                  <div className="flex items-center space-x-3 mb-3">
                    <div className="h-10 w-10 bg-green-100 rounded-lg flex items-center justify-center">
                      <Gauge className="h-5 w-5 text-green-700" />
                    </div>
                    <CardTitle className="text-lg text-gray-900">Performance Metrics</CardTitle>
                  </div>
                  <CardDescription className="text-gray-600 space-y-2">
                    <div className="flex items-center text-sm">
                      <CheckCircle className="h-4 w-4 mr-2 text-green-600" />
                      Mobile & Desktop Scores
                    </div>
                    <div className="flex items-center text-sm">
                      <CheckCircle className="h-4 w-4 mr-2 text-green-600" />
                      Core Web Vitals (LCP, CLS, INP)
                    </div>
                    <div className="flex items-center text-sm">
                      <CheckCircle className="h-4 w-4 mr-2 text-green-600" />
                      Loading Times & Metrics
                    </div>
                  </CardDescription>
                </CardHeader>
              </Card>

              {/* Screenshots */}
              <Card className="border-gray-200 hover:shadow-md transition-shadow">
                <CardHeader>
                  <div className="flex items-center space-x-3 mb-3">
                    <div className="h-10 w-10 bg-blue-100 rounded-lg flex items-center justify-center">
                      <Camera className="h-5 w-5 text-blue-700" />
                    </div>
                    <CardTitle className="text-lg text-gray-900">Visual Analysis</CardTitle>
                  </div>
                  <CardDescription className="text-gray-600 space-y-2">
                    <div className="flex items-center text-sm">
                      <CheckCircle className="h-4 w-4 mr-2 text-green-600" />
                      Mobile & Desktop Screenshots
                    </div>
                    <div className="flex items-center text-sm">
                      <CheckCircle className="h-4 w-4 mr-2 text-green-600" />
                      Loading Filmstrip
                    </div>
                    <div className="flex items-center text-sm">
                      <CheckCircle className="h-4 w-4 mr-2 text-green-600" />
                      LCP Element Highlighting
                    </div>
                  </CardDescription>
                </CardHeader>
              </Card>

              {/* Opportunities */}
              <Card className="border-gray-200 hover:shadow-md transition-shadow">
                <CardHeader>
                  <div className="flex items-center space-x-3 mb-3">
                    <div className="h-10 w-10 bg-purple-100 rounded-lg flex items-center justify-center">
                      <TrendingUp className="h-5 w-5 text-purple-700" />
                    </div>
                    <CardTitle className="text-lg text-gray-900">Optimization Tips</CardTitle>
                  </div>
                  <CardDescription className="text-gray-600 space-y-2">
                    <div className="flex items-center text-sm">
                      <CheckCircle className="h-4 w-4 mr-2 text-green-600" />
                      Top 10 Opportunities
                    </div>
                    <div className="flex items-center text-sm">
                      <CheckCircle className="h-4 w-4 mr-2 text-green-600" />
                      Time & Byte Savings
                    </div>
                    <div className="flex items-center text-sm">
                      <CheckCircle className="h-4 w-4 mr-2 text-green-600" />
                      Affected Resources
                    </div>
                  </CardDescription>
                </CardHeader>
              </Card>

              {/* Security */}
              <Card className="border-gray-200 hover:shadow-md transition-shadow">
                <CardHeader>
                  <div className="flex items-center space-x-3 mb-3">
                    <div className="h-10 w-10 bg-red-100 rounded-lg flex items-center justify-center">
                      <Shield className="h-5 w-5 text-red-700" />
                    </div>
                    <CardTitle className="text-lg text-gray-900">Security Scan</CardTitle>
                  </div>
                  <CardDescription className="text-gray-600 space-y-2">
                    <div className="flex items-center text-sm">
                      <CheckCircle className="h-4 w-4 mr-2 text-green-600" />
                      Vulnerability Detection
                    </div>
                    <div className="flex items-center text-sm">
                      <CheckCircle className="h-4 w-4 mr-2 text-green-600" />
                      Exposed Files & Directories
                    </div>
                    <div className="flex items-center text-sm">
                      <CheckCircle className="h-4 w-4 mr-2 text-green-600" />
                      Security Headers Analysis
                    </div>
                  </CardDescription>
                </CardHeader>
              </Card>

              {/* SEO */}
              <Card className="border-gray-200 hover:shadow-md transition-shadow">
                <CardHeader>
                  <div className="flex items-center space-x-3 mb-3">
                    <div className="h-10 w-10 bg-yellow-100 rounded-lg flex items-center justify-center">
                      <Eye className="h-5 w-5 text-yellow-700" />
                    </div>
                    <CardTitle className="text-lg text-gray-900">SEO Analysis</CardTitle>
                  </div>
                  <CardDescription className="text-gray-600 space-y-2">
                    <div className="flex items-center text-sm">
                      <CheckCircle className="h-4 w-4 mr-2 text-green-600" />
                      Meta Tags & Schema
                    </div>
                    <div className="flex items-center text-sm">
                      <CheckCircle className="h-4 w-4 mr-2 text-green-600" />
                      Open Graph & Twitter Cards
                    </div>
                    <div className="flex items-center text-sm">
                      <CheckCircle className="h-4 w-4 mr-2 text-green-600" />
                      Content Structure
                    </div>
                  </CardDescription>
                </CardHeader>
              </Card>

              {/* Revenue Calculator */}
              <Card className="border-gray-200 hover:shadow-md transition-shadow">
                <CardHeader>
                  <div className="flex items-center space-x-3 mb-3">
                    <div className="h-10 w-10 bg-orange-100 rounded-lg flex items-center justify-center">
                      <DollarSign className="h-5 w-5 text-orange-700" />
                    </div>
                    <CardTitle className="text-lg text-gray-900">Revenue Impact</CardTitle>
                  </div>
                  <CardDescription className="text-gray-600 space-y-2">
                    <div className="flex items-center text-sm">
                      <CheckCircle className="h-4 w-4 mr-2 text-green-600" />
                      Lost Revenue Calculator
                    </div>
                    <div className="flex items-center text-sm">
                      <CheckCircle className="h-4 w-4 mr-2 text-green-600" />
                      Conversion Rate Impact
                    </div>
                    <div className="flex items-center text-sm">
                      <CheckCircle className="h-4 w-4 mr-2 text-green-600" />
                      Recovery Potential
                    </div>
                  </CardDescription>
                </CardHeader>
              </Card>
            </div>
          </div>

          {/* CTA Section */}
          <div className="max-w-4xl mx-auto bg-gray-900 rounded-2xl p-12 text-center">
            <h2 className="text-3xl font-bold text-white mb-4">
              Ready to Speed Up Your WordPress Site?
            </h2>
            <p className="text-lg text-gray-300 mb-8">
              Get your free audit report in 60 seconds. No signup required.
            </p>
            <div className="max-w-lg mx-auto">
              <div className="flex gap-3 p-2 bg-white rounded-lg shadow-lg">
                <Input
                  type="url"
                  placeholder="Enter your WordPress URL..."
                  value={url}
                  onChange={(e) => setUrl(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && handleScan()}
                  className="flex-1 border-0 focus-visible:ring-0 focus-visible:ring-offset-0"
                />
                <Button 
                  onClick={handleScan}
                  disabled={!url || isScanning}
                  size="lg"
                  className="px-6 bg-black hover:bg-gray-800 text-white"
                >
                  {isScanning ? 'Analyzing...' : 'Analyze Now'}
                  <ArrowRight className="ml-2 h-4 w-4" />
                </Button>
              </div>
            </div>
          </div>
        </div>
      </main>

      {/* Footer */}
      <footer className="border-t border-gray-200 bg-white mt-24">
        <div className="container mx-auto px-4 py-12">
          <div className="flex flex-col md:flex-row justify-between items-center">
            <div className="flex items-center space-x-2 mb-4 md:mb-0">
              <div className="h-6 w-6 bg-black rounded flex items-center justify-center">
                <Zap className="h-4 w-4 text-white" />
              </div>
              <span className="font-semibold text-gray-900">Just Speed It</span>
            </div>
            
            <div className="flex items-center space-x-6 text-sm text-gray-600">
              <a href="#" className="hover:text-gray-900 transition-colors">Documentation</a>
              <a href="#" className="hover:text-gray-900 transition-colors">API</a>
              <a href="#" className="hover:text-gray-900 transition-colors">Privacy</a>
              <a href="#" className="hover:text-gray-900 transition-colors">Terms</a>
            </div>
          </div>
          
          <div className="mt-8 pt-8 border-t border-gray-100 text-center text-sm text-gray-500">
            <p>&copy; {new Date().getFullYear()} Just Speed It. Free WordPress Performance Audits Powered by Google Lighthouse.</p>
          </div>
        </div>
      </footer>
    </div>
  )
}
