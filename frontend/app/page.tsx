'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { AppHeader } from '@/components/layout/AppHeader'
import { AppFooter } from '@/components/layout/AppFooter'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { 
  Zap, 
  ArrowRight,
  CheckCircle,
  Gauge,
  Shield,
  TrendingUp,
  Clock,
  Star,
  Sparkles,
  BarChart3,
  Globe
} from 'lucide-react'

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
    <div className="min-h-screen bg-white">
      
      <AppHeader variant="landing" transparent />

      {/* Hero Section */}
      <section className="pt-32 pb-20 px-4 relative overflow-hidden">
        {/* Background gradient */}
        <div className="absolute inset-0 bg-gradient-to-b from-emerald-50/50 via-white to-white"></div>
        <div className="absolute top-0 left-1/4 w-96 h-96 bg-emerald-200/30 rounded-full blur-3xl"></div>
        <div className="absolute top-20 right-1/4 w-96 h-96 bg-teal-200/20 rounded-full blur-3xl"></div>
        
        <div className="container mx-auto max-w-6xl relative z-10">
          <div className="text-center max-w-4xl mx-auto mb-12">
            {/* Badge */}
            <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-emerald-50 border border-emerald-100 mb-6">
              <Sparkles className="h-4 w-4 text-emerald-600" />
              <span className="text-sm font-medium text-emerald-900">Powered by Google Lighthouse</span>
            </div>

            {/* Main Headline */}
            <h1 className="text-5xl md:text-6xl lg:text-7xl font-bold text-gray-900 mb-6 leading-tight">
              Stop Guessing. Start Fixing.
              <span className="block mt-2 bg-gradient-to-r from-emerald-600 to-teal-600 bg-clip-text text-transparent">
                Get Your Free WordPress Performance Audit.
              </span>
            </h1>

            {/* Subheadline */}
            <p className="text-xl md:text-2xl text-gray-600 mb-8 leading-relaxed">
              Get a complete <span className="font-semibold text-gray-900">Performance, Security, and SEO</span> analysis in under 60 seconds. 
              We find the bottlenecks so you can get back to growing. 
              <span className="font-semibold text-gray-900"> No email required.</span>
            </p>

            {/* Audit Form */}
            <div id="audit-form" className="max-w-2xl mx-auto">
              <div className="bg-white rounded-2xl shadow-xl border border-gray-100 p-3">
                <div className="flex flex-col sm:flex-row gap-3">
                  <Input
                    type="text"
                    placeholder="Enter your WordPress URL (e.g., example.com)"
                    value={url}
                    onChange={(e) => setUrl(e.target.value)}
                    onKeyDown={(e) => e.key === 'Enter' && handleScan()}
                    className="flex-1 h-12 text-base border-0 focus-visible:ring-0 focus-visible:ring-offset-0"
                  />
                  <Button
                    onClick={handleScan}
                    disabled={!url || isScanning}
                    size="lg"
                    className="h-12 px-8 bg-gradient-to-r from-emerald-600 to-teal-600 hover:from-emerald-700 hover:to-teal-700 text-white font-semibold"
                  >
                    {isScanning ? (
                      <>
                        <Clock className="mr-2 h-4 w-4 animate-spin" />
                        Analyzing...
                      </>
                    ) : (
                      <>
                        Test My Site
                        <ArrowRight className="ml-2 h-4 w-4" />
                      </>
                    )}
                  </Button>
                </div>
              </div>
              
              {/* Trust badges */}
              <div className="flex items-center justify-center gap-6 mt-6 text-sm text-gray-500">
                <div className="flex items-center gap-2">
                  <CheckCircle className="h-4 w-4 text-emerald-600" />
                  <span>100% Free</span>
                </div>
                <div className="flex items-center gap-2">
                  <CheckCircle className="h-4 w-4 text-emerald-600" />
                  <span>No Signup</span>
                </div>
                <div className="flex items-center gap-2">
                  <CheckCircle className="h-4 w-4 text-emerald-600" />
                  <span>Results in 60s</span>
                </div>
              </div>
            </div>
          </div>

          {/* Stats Row */}
          <div className="grid grid-cols-3 gap-6 max-w-3xl mx-auto mt-16">
            <div className="text-center">
              <div className="text-3xl md:text-4xl font-bold text-gray-900 mb-2">10K+</div>
              <div className="text-sm text-gray-600">Sites Analyzed</div>
            </div>
            <div className="text-center">
              <div className="text-3xl md:text-4xl font-bold text-gray-900 mb-2">&lt;60s</div>
              <div className="text-sm text-gray-600">Actionable Report</div>
            </div>
            <div className="text-center">
              <div className="text-3xl md:text-4xl font-bold text-gray-900 mb-2">100%</div>
              <div className="text-sm text-gray-600">Completely Free. No Upsells.</div>
            </div>
          </div>
        </div>
      </section>

      {/* Problem Section */}
      <section className="py-20 px-4 bg-gray-50">
        <div className="container mx-auto max-w-6xl">
          <div className="text-center mb-4">
            <h2 className="text-3xl md:text-4xl font-bold text-gray-900 mb-4">
              Performance Isn't a Feature. It's Your Foundation.
            </h2>
            <p className="text-lg text-gray-600 max-w-3xl mx-auto mb-12">
              Slow sites don't just feel bad—they kill your metrics. Here's why every second counts.
            </p>
          </div>

          <div className="grid md:grid-cols-3 gap-8">
            {/* Problem 1 */}
            <div className="bg-white rounded-2xl p-8 border border-gray-100 hover:shadow-lg transition-shadow">
              <div className="w-12 h-12 bg-red-100 rounded-xl flex items-center justify-center mb-6">
                <TrendingUp className="h-6 w-6 text-red-600" />
              </div>
              <h3 className="text-xl font-bold text-gray-900 mb-3">You're Losing Customers</h3>
              <p className="text-gray-600 mb-4 leading-relaxed">
                A 1-second delay in mobile load times can impact conversion rates by up to 20%.
              </p>
              <div className="text-xs text-gray-500 italic">Source: Google</div>
            </div>

            {/* Problem 2 */}
            <div className="bg-white rounded-2xl p-8 border border-gray-100 hover:shadow-lg transition-shadow">
              <div className="w-12 h-12 bg-orange-100 rounded-xl flex items-center justify-center mb-6">
                <BarChart3 className="h-6 w-6 text-orange-600" />
              </div>
              <h3 className="text-xl font-bold text-gray-900 mb-3">Your Rankings Suffer</h3>
              <p className="text-gray-600 mb-4 leading-relaxed">
                Page speed is a critical Google ranking factor for both desktop and mobile search. If you're slow, you're invisible.
              </p>
            </div>

            {/* Problem 3 */}
            <div className="bg-white rounded-2xl p-8 border border-gray-100 hover:shadow-lg transition-shadow">
              <div className="w-12 h-12 bg-red-100 rounded-xl flex items-center justify-center mb-6">
                <Globe className="h-6 w-6 text-red-600" />
              </div>
              <h3 className="text-xl font-bold text-gray-900 mb-3">Revenue Disappears</h3>
              <p className="text-gray-600 mb-4 leading-relaxed">
                For e-commerce, the first 5 seconds of load time are crucial. Conversion rates can drop by over 4.4% for every extra second.
              </p>
              <div className="text-xs text-gray-500 italic">Source: Portent</div>
            </div>
          </div>
        </div>
      </section>

      {/* Solution Section */}
      <section className="py-20 px-4">
        <div className="container mx-auto max-w-6xl">
          <div className="text-center mb-4">
            <h2 className="text-3xl md:text-4xl font-bold text-gray-900 mb-4">
              More Than a Speed Test. It's a Full Diagnosis.
            </h2>
            <p className="text-lg text-gray-600 max-w-3xl mx-auto mb-16">
              Our audit goes beyond a simple Lighthouse score. We check your entire WordPress stack.
            </p>
          </div>

          <div className="grid md:grid-cols-2 gap-8">
            {/* Feature 1 */}
            <div className="group">
              <div className="bg-gradient-to-br from-emerald-50 to-teal-50 rounded-2xl p-8 border border-emerald-100 hover:shadow-xl transition-all">
                <div className="w-14 h-14 bg-white rounded-xl flex items-center justify-center mb-6 shadow-sm">
                  <Gauge className="h-7 w-7 text-emerald-600" />
                </div>
                <h3 className="text-2xl font-bold text-gray-900 mb-3">Core Web Vitals Diagnosis</h3>
                <p className="text-gray-700 mb-6 leading-relaxed">
                  Get precise measurements of Google's performance metrics that directly impact your search rankings.
                </p>
                <ul className="space-y-3">
                  <li className="flex items-start gap-3 text-gray-700">
                    <CheckCircle className="h-5 w-5 text-emerald-600 flex-shrink-0 mt-0.5" />
                    <span>Pinpoint LCP (Largest Contentful Paint) issues</span>
                  </li>
                  <li className="flex items-start gap-3 text-gray-700">
                    <CheckCircle className="h-5 w-5 text-emerald-600 flex-shrink-0 mt-0.5" />
                    <span>Identify FID/INP (Interaction to Next Paint) bottlenecks</span>
                  </li>
                  <li className="flex items-start gap-3 text-gray-700">
                    <CheckCircle className="h-5 w-5 text-emerald-600 flex-shrink-0 mt-0.5" />
                    <span>Detect CLS (Cumulative Layout Shift) layout shifts</span>
                  </li>
                </ul>
              </div>
            </div>

            {/* Feature 2 */}
            <div className="group">
              <div className="bg-gradient-to-br from-blue-50 to-cyan-50 rounded-2xl p-8 border border-blue-100 hover:shadow-xl transition-all">
                <div className="w-14 h-14 bg-white rounded-xl flex items-center justify-center mb-6 shadow-sm">
                  <Shield className="h-7 w-7 text-blue-600" />
                </div>
                <h3 className="text-2xl font-bold text-gray-900 mb-3">Security & Vulnerability Scan</h3>
                <p className="text-gray-700 mb-6 leading-relaxed">
                  Identify potential security risks that could compromise your site or hurt your SEO rankings.
                </p>
                <ul className="space-y-3">
                  <li className="flex items-start gap-3 text-gray-700">
                    <CheckCircle className="h-5 w-5 text-blue-600 flex-shrink-0 mt-0.5" />
                    <span>Check for outdated plugins & WordPress core</span>
                  </li>
                  <li className="flex items-start gap-3 text-gray-700">
                    <CheckCircle className="h-5 w-5 text-blue-600 flex-shrink-0 mt-0.5" />
                    <span>Scan for common malware signatures</span>
                  </li>
                  <li className="flex items-start gap-3 text-gray-700">
                    <CheckCircle className="h-5 w-5 text-blue-600 flex-shrink-0 mt-0.5" />
                    <span>Analyze critical security headers (HSTS, CSP)</span>
                  </li>
                </ul>
              </div>
            </div>

            {/* Feature 3 */}
            <div className="group">
              <div className="bg-gradient-to-br from-purple-50 to-pink-50 rounded-2xl p-8 border border-purple-100 hover:shadow-xl transition-all">
                <div className="w-14 h-14 bg-white rounded-xl flex items-center justify-center mb-6 shadow-sm">
                  <TrendingUp className="h-7 w-7 text-purple-600" />
                </div>
                <h3 className="text-2xl font-bold text-gray-900 mb-3">On-Page SEO Audit</h3>
                <p className="text-gray-700 mb-6 leading-relaxed">
                  Ensure your WordPress site has the essential SEO elements configured correctly for maximum visibility.
                </p>
                <ul className="space-y-3">
                  <li className="flex items-start gap-3 text-gray-700">
                    <CheckCircle className="h-5 w-5 text-purple-600 flex-shrink-0 mt-0.5" />
                    <span>Verify essential meta tags (Title & Description)</span>
                  </li>
                  <li className="flex items-start gap-3 text-gray-700">
                    <CheckCircle className="h-5 w-5 text-purple-600 flex-shrink-0 mt-0.5" />
                    <span>Check for correct header (H1/H2) structure</span>
                  </li>
                  <li className="flex items-start gap-3 text-gray-700">
                    <CheckCircle className="h-5 w-5 text-purple-600 flex-shrink-0 mt-0.5" />
                    <span>Analyze image alt-tags and robots.txt configuration</span>
                  </li>
                </ul>
              </div>
            </div>

            {/* Feature 4 */}
            <div className="group">
              <div className="bg-gradient-to-br from-orange-50 to-amber-50 rounded-2xl p-8 border border-orange-100 hover:shadow-xl transition-all">
                <div className="w-14 h-14 bg-white rounded-xl flex items-center justify-center mb-6 shadow-sm">
                  <Zap className="h-7 w-7 text-orange-600" />
                </div>
                <h3 className="text-2xl font-bold text-gray-900 mb-3">WordPress Technical Deep Dive</h3>
                <p className="text-gray-700 mb-6 leading-relaxed">
                  Get WordPress-specific insights that generic speed tests miss—plugin analysis, resource optimization, and more.
                </p>
                <ul className="space-y-3">
                  <li className="flex items-start gap-3 text-gray-700">
                    <CheckCircle className="h-5 w-5 text-orange-600 flex-shrink-0 mt-0.5" />
                    <span>Identify slow-loading or "heavy" plugins</span>
                  </li>
                  <li className="flex items-start gap-3 text-gray-700">
                    <CheckCircle className="h-5 w-5 text-orange-600 flex-shrink-0 mt-0.5" />
                    <span>Analyze image formats and compression levels</span>
                  </li>
                  <li className="flex items-start gap-3 text-gray-700">
                    <CheckCircle className="h-5 w-5 text-orange-600 flex-shrink-0 mt-0.5" />
                    <span>Check for render-blocking resources (CSS/JS)</span>
                  </li>
                </ul>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* How It Works */}
      <section className="py-20 px-4 bg-gray-50">
        <div className="container mx-auto max-w-5xl">
          <div className="text-center mb-16">
            <h2 className="text-3xl md:text-4xl font-bold text-gray-900 mb-4">
              How It Works
            </h2>
            <p className="text-lg text-gray-600">
              Get comprehensive insights in three simple steps
            </p>
          </div>

          <div className="grid md:grid-cols-3 gap-8">
            <div className="text-center">
              <div className="w-16 h-16 bg-gradient-to-br from-emerald-500 to-teal-600 rounded-2xl flex items-center justify-center mx-auto mb-6 shadow-lg">
                <span className="text-2xl font-bold text-white">1</span>
              </div>
              <h3 className="text-xl font-bold text-gray-900 mb-3">Enter Your URL</h3>
              <p className="text-gray-600">
                Simply paste your WordPress site URL - no signup or configuration needed
              </p>
            </div>

            <div className="text-center">
              <div className="w-16 h-16 bg-gradient-to-br from-emerald-500 to-teal-600 rounded-2xl flex items-center justify-center mx-auto mb-6 shadow-lg">
                <span className="text-2xl font-bold text-white">2</span>
              </div>
              <h3 className="text-xl font-bold text-gray-900 mb-3">We Analyze</h3>
              <p className="text-gray-600">
                Our AI-powered engine runs a comprehensive audit using Google Lighthouse
              </p>
            </div>

            <div className="text-center">
              <div className="w-16 h-16 bg-gradient-to-br from-emerald-500 to-teal-600 rounded-2xl flex items-center justify-center mx-auto mb-6 shadow-lg">
                <span className="text-2xl font-bold text-white">3</span>
              </div>
              <h3 className="text-xl font-bold text-gray-900 mb-3">Get Results</h3>
              <p className="text-gray-600">
                Receive actionable insights and optimization recommendations in under 60 seconds
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Authority Section */}
      <section className="py-20 px-4">
        <div className="container mx-auto max-w-5xl">
          <div className="bg-gradient-to-br from-gray-50 to-gray-100 rounded-3xl p-12 md:p-16 border border-gray-200">
            <div className="text-center max-w-3xl mx-auto">
              <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-emerald-100 border border-emerald-200 mb-6">
                <Star className="h-4 w-4 text-emerald-600" />
                <span className="text-sm font-semibold text-emerald-900">Built by WordPress Experts</span>
              </div>
              
              <h2 className="text-3xl md:text-4xl font-bold text-gray-900 mb-6">
                An Expert Tool from WordPress Experts
              </h2>
              
              <p className="text-lg text-gray-700 leading-relaxed mb-8">
                Just Speed It isn't just another script. It's built and maintained by the team at{' '}
                <a 
                  href="https://justwpit.com" 
                  target="_blank" 
                  rel="noopener noreferrer"
                  className="font-semibold text-emerald-600 hover:text-emerald-700 underline decoration-emerald-300 decoration-2 underline-offset-2 transition-colors"
                >
                  JustWPit.com
                </a>
                , a dedicated WordPress agency with nearly a decade of experience optimizing high-traffic, complex websites.
              </p>
              
              <p className="text-lg text-gray-700 leading-relaxed">
                We built this tool because we use this diagnostic process for our own clients every day. 
                <span className="font-semibold text-gray-900"> You're getting an agency-level audit, for free.</span>
              </p>
              
              <div className="mt-10 pt-8 border-t border-gray-300">
                <div className="flex items-center justify-center gap-3">
                  <div className="w-12 h-12 bg-gradient-to-br from-emerald-500 to-teal-600 rounded-xl flex items-center justify-center">
                    <Zap className="h-6 w-6 text-white" />
                  </div>
                  <div className="text-left">
                    <div className="font-bold text-xl text-gray-900">JustWPit.com</div>
                    <div className="text-sm text-gray-600">WordPress Performance Agency</div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* CTA Section */}
      <section className="py-20 px-4">
        <div className="container mx-auto max-w-4xl">
          <div className="bg-gradient-to-br from-emerald-600 to-teal-600 rounded-3xl p-12 md:p-16 text-center text-white shadow-2xl">
            <h2 className="text-3xl md:text-4xl font-bold mb-6">
              Ready to See the Full Picture?
            </h2>
            <p className="text-xl mb-8 text-emerald-50">
              Get your free, instant, and actionable WordPress audit. No email. No catch.
            </p>
            <Button
              size="lg"
              onClick={() => document.getElementById('audit-form')?.scrollIntoView({ behavior: 'smooth' })}
              className="h-14 px-8 bg-white text-emerald-600 hover:bg-gray-100 font-semibold text-lg shadow-xl"
            >
              Test Your Site Now
              <ArrowRight className="ml-2 h-5 w-5" />
            </Button>
          </div>
        </div>
      </section>

      <AppFooter />

    </div>
  )
}
