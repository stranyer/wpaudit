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
  BarChart3
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
              <span className="text-xl font-semibold text-gray-900">Just Audit It</span>
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
            WordPress Audit.
            <br />
            <span className="text-gray-400">Done Right.</span>
          </h1>
          
          <p className="text-xl text-center text-gray-600 mb-12 max-w-2xl mx-auto">
            Get a comprehensive performance, SEO, and security audit in 60 seconds. 
            <span className="font-medium text-gray-900"> No fluff, just actionable insights.</span>
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

          {/* What You Get Section */}
          <div className="max-w-4xl mx-auto bg-gray-50 rounded-2xl p-12 border border-gray-200">
            <div className="text-center mb-12">
              <h2 className="text-3xl font-bold text-gray-900 mb-4">
                What's in Your Audit
              </h2>
              <p className="text-gray-600">
                Everything you need to fix performance, security, and SEO issues
              </p>
            </div>

            <div className="grid md:grid-cols-2 gap-8">
              {/* Left Column */}
              <div className="space-y-6">
                <div className="flex items-start space-x-3">
                  <div className="h-6 w-6 bg-black rounded flex items-center justify-center flex-shrink-0 mt-0.5">
                    <CheckCircle className="h-4 w-4 text-white" />
                  </div>
                  <div>
                    <h4 className="font-semibold text-gray-900 mb-1">Core Web Vitals</h4>
                    <p className="text-sm text-gray-600">
                      Real LCP, CLS, and INP metrics from Google Lighthouse
                    </p>
                  </div>
                </div>

                <div className="flex items-start space-x-3">
                  <div className="h-6 w-6 bg-black rounded flex items-center justify-center flex-shrink-0 mt-0.5">
                    <CheckCircle className="h-4 w-4 text-white" />
                  </div>
                  <div>
                    <h4 className="font-semibold text-gray-900 mb-1">Security Scan</h4>
                    <p className="text-sm text-gray-600">
                      Exposed files, vulnerable plugins, and outdated software
                    </p>
                  </div>
                </div>

                <div className="flex items-start space-x-3">
                  <div className="h-6 w-6 bg-black rounded flex items-center justify-center flex-shrink-0 mt-0.5">
                    <CheckCircle className="h-4 w-4 text-white" />
                  </div>
                  <div>
                    <h4 className="font-semibold text-gray-900 mb-1">SEO Analysis</h4>
                    <p className="text-sm text-gray-600">
                      Meta tags, schema, indexability, and content structure
                    </p>
                  </div>
                </div>
              </div>

              {/* Right Column */}
              <div className="space-y-6">
                <div className="flex items-start space-x-3">
                  <div className="h-6 w-6 bg-black rounded flex items-center justify-center flex-shrink-0 mt-0.5">
                    <CheckCircle className="h-4 w-4 text-white" />
                  </div>
                  <div>
                    <h4 className="font-semibold text-gray-900 mb-1">Plugin Detection</h4>
                    <p className="text-sm text-gray-600">
                      Identify all plugins, themes, and their impact on performance
                    </p>
                  </div>
                </div>

                <div className="flex items-start space-x-3">
                  <div className="h-6 w-6 bg-black rounded flex items-center justify-center flex-shrink-0 mt-0.5">
                    <CheckCircle className="h-4 w-4 text-white" />
                  </div>
                  <div>
                    <h4 className="font-semibold text-gray-900 mb-1">GDPR Compliance</h4>
                    <p className="text-sm text-gray-600">
                      Privacy policy, cookie notices, and tracking scripts
                    </p>
                  </div>
                </div>

                <div className="flex items-start space-x-3">
                  <div className="h-6 w-6 bg-black rounded flex items-center justify-center flex-shrink-0 mt-0.5">
                    <CheckCircle className="h-4 w-4 text-white" />
                  </div>
                  <div>
                    <h4 className="font-semibold text-gray-900 mb-1">Actionable Insights</h4>
                    <p className="text-sm text-gray-600">
                      Prioritized fixes with effort estimates and impact ratings
                    </p>
                  </div>
                </div>
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
              <span className="font-semibold text-gray-900">Just Audit It</span>
            </div>
            
            <div className="flex items-center space-x-6 text-sm text-gray-600">
              <a href="#" className="hover:text-gray-900 transition-colors">Documentation</a>
              <a href="#" className="hover:text-gray-900 transition-colors">API</a>
              <a href="#" className="hover:text-gray-900 transition-colors">Privacy</a>
              <a href="#" className="hover:text-gray-900 transition-colors">Terms</a>
            </div>
          </div>
          
          <div className="mt-8 pt-8 border-t border-gray-100 text-center text-sm text-gray-500">
            <p>&copy; {new Date().getFullYear()} Just Audit It. Built with Lighthouse & shadcn/ui.</p>
          </div>
        </div>
      </footer>
    </div>
  )
}
