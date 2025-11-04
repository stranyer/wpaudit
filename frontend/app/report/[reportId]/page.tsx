'use client'

import { useState, useEffect } from 'react'
import { useParams } from 'next/navigation'
import { AppHeader } from '@/components/layout/AppHeader'
import { AppFooter } from '@/components/layout/AppFooter'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { 
  Zap, 
  Shield, 
  Eye, 
  CheckCircle, 
  AlertTriangle, 
  Clock,
  Download,
  ExternalLink,
  Smartphone,
  Monitor,
  TrendingUp,
  Target,
  Activity,
  Globe,
  Lock,
  Users,
  Share2,
  Twitter,
  Linkedin,
  Link as LinkIcon,
  Copy,
  DollarSign,
  TrendingDown,
  Calculator
} from 'lucide-react'

interface ReportData {
  meta: {
    scannedAt: string
    url: string
  }
  wordpress: {
    isWordPress: boolean
    version?: string
    theme?: {
      name: string
      child: boolean
    }
    plugins?: Array<{
      slug: string
      confidence: number
      impact: 'low' | 'medium' | 'high'
    }>
  }
  performance: {
    scores: {
      mobile: number
      desktop: number
    }
    coreWebVitals: {
      lcp: number
      cls: number
      inp: number
    }
    requests: number
    transferMB: number
    ttfb?: number
    fcp?: number
    si?: number
    tti?: number
    tbt?: number
    imageSize?: number
    scriptSize?: number
    cssSize?: number
    screenshots?: {
      mobile?: string
      desktop?: string
    }
    filmstrip?: {
      mobile?: string[]
      desktop?: string[]
    }
    opportunities?: Array<{
      id: string
      title: string
      description: string
      savings: {
        ms: number
        bytes: number
      }
      items: any[]
    }>
  }
  seo: {
    score: number
    title: {
      present: boolean
      length: number
      optimal: boolean
    }
    metaDescription: {
      present: boolean
      length: number
      optimal: boolean
    }
    headings: {
      h1Count: number
      h1Text: string
      hasSingleH1: boolean
    }
    canonical: boolean
    robots: string
    openGraph: {
      title: boolean
      description: boolean
      image: boolean
    }
    twitterCard: boolean
    schemas: string[]
    images: {
      total: number
      withoutAlt: number
      altPercentage: number
    }
    links: {
      internal: number
      external: number
    }
  }
  security: {
    score: number
    xmlrpc: string
    readme: string
    wpConfig: string
    headers: {
      csp: boolean
      xFrameOptions: boolean
      xContentTypeOptions: boolean
      xXssProtection: boolean
      strictTransportSecurity: boolean
      referrerPolicy: boolean
    }
    wordpressVersion: {
      exposed: boolean
      version?: string
      isOld: boolean
    }
  }
  accessibility: {
    score: number
    lang: boolean
    images: {
      total: number
      withoutAlt: number
      altPercentage: number
    }
    forms: {
      total: number
      withLabels: number
      labelPercentage: number
    }
    contrast: boolean
  }
  gdpr: {
    score: number
    privacyPolicy: boolean
    cookieNotice: boolean
    contactInfo: boolean
    imprint: boolean
    tracking: {
      present: boolean
      scripts: number
    }
  }
  priorities: Array<{
    title: string
    impact: 'high' | 'medium' | 'low'
    effort: 'XS' | 'S' | 'M' | 'L'
    why: string
  }>
  estimation: {
    hours: number
    bundle: string
  }
}

export default function ReportPage() {
  const params = useParams()
  const [report, setReport] = useState<ReportData | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [copied, setCopied] = useState(false)
  const [monthlyVisitors, setMonthlyVisitors] = useState(10000)
  const [conversionRate, setConversionRate] = useState(2)
  const [avgOrderValue, setAvgOrderValue] = useState(50)

  const shareUrl = typeof window !== 'undefined' ? window.location.href : ''
  
  const shareOnTwitter = () => {
    if (!report) return
    const text = `I just audited ${new URL(report.meta.url).hostname} with @JustAuditIt!\n\n📊 Performance: ${Math.round((report.performance.scores.mobile + report.performance.scores.desktop) / 2)}/100\n🔒 Security: ${report.security.score}/100\n📈 SEO: ${report.seo.score}/100\n\nCheck your site:`
    const url = `https://twitter.com/intent/tweet?text=${encodeURIComponent(text)}&url=${encodeURIComponent(shareUrl)}`
    window.open(url, '_blank', 'width=550,height=420')
  }

  const shareOnLinkedIn = () => {
    if (!report) return
    const url = `https://www.linkedin.com/sharing/share-offsite/?url=${encodeURIComponent(shareUrl)}`
    window.open(url, '_blank', 'width=550,height=420')
  }

  const copyLink = async () => {
    try {
      await navigator.clipboard.writeText(shareUrl)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch (err) {
      console.error('Failed to copy:', err)
    }
  }

  const calculateRevenueLoss = () => {
    if (!report) return { monthly: 0, yearly: 0, conversionLoss: 0, bounceIncrease: 0 }
    
    const avgScore = (report.performance.scores.mobile + report.performance.scores.desktop) / 2
    const lcpSeconds = report.performance.coreWebVitals.lcp
    
    let conversionDropPercent = 0
    if (avgScore < 50) conversionDropPercent = 20
    else if (avgScore < 70) conversionDropPercent = 12
    else if (avgScore < 90) conversionDropPercent = 7
    else conversionDropPercent = 2
    
    if (lcpSeconds > 4) conversionDropPercent += 10
    else if (lcpSeconds > 2.5) conversionDropPercent += 5
    
    const monthlyConversions = (monthlyVisitors * conversionRate) / 100
    const lostConversions = (monthlyConversions * conversionDropPercent) / 100
    const monthlyLoss = lostConversions * avgOrderValue
    const yearlyLoss = monthlyLoss * 12
    
    const bounceIncrease = avgScore < 50 ? 32 : avgScore < 70 ? 20 : avgScore < 90 ? 10 : 3
    
    return {
      monthly: Math.round(monthlyLoss),
      yearly: Math.round(yearlyLoss),
      conversionLoss: Math.round(lostConversions),
      bounceIncrease
    }
  }

  const revenueLoss = calculateRevenueLoss()

  useEffect(() => {
    if (!params.reportId || params.reportId === 'undefined') {
      setError('Invalid report ID')
      setLoading(false)
      return
    }

    const fetchReport = async () => {
      try {
        console.log('Fetching report for ID:', params.reportId)
        const response = await fetch(`/api/report/${params.reportId}`)
        console.log('Report response status:', response.status)
        
        if (!response.ok) {
          throw new Error(`Failed to fetch report: ${response.status}`)
        }
        
        const data = await response.json()
        console.log('Report data received:', data)
        setReport(data.data)
      } catch (err) {
        console.error('Error fetching report:', err)
        setError(err instanceof Error ? err.message : 'Failed to load report')
      } finally {
        setLoading(false)
      }
    }

    fetchReport()
  }, [params.reportId])

  const getScoreColor = (score: number) => {
    if (score >= 90) return 'text-green-600'
    if (score >= 70) return 'text-yellow-600'
    return 'text-red-600'
  }

  const getScoreBorderColor = (score: number) => {
    if (score >= 90) return 'border-green-600'
    if (score >= 70) return 'border-yellow-600'
    return 'border-red-600'
  }

  const getScoreBadge = (score: number) => {
    if (score >= 90) return 'bg-green-100 text-green-800'
    if (score >= 70) return 'bg-yellow-100 text-yellow-800'
    return 'bg-red-100 text-red-800'
  }

  const getScoreLabel = (score: number) => {
    if (score >= 90) return 'Good'
    if (score >= 70) return 'Needs Work'
    return 'Poor'
  }

  const getImpactBadge = (impact: string) => {
    switch (impact) {
      case 'high': return 'bg-red-100 text-red-800'
      case 'medium': return 'bg-yellow-100 text-yellow-800'
      case 'low': return 'bg-green-100 text-green-800'
      default: return 'bg-gray-100 text-gray-800'
    }
  }

  if (loading) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600 mx-auto mb-4"></div>
          <p className="text-gray-600">Loading report...</p>
        </div>
      </div>
    )
  }

  if (error || !report) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <div className="text-center">
          <AlertTriangle className="h-12 w-12 text-red-500 mx-auto mb-4" />
          <h1 className="text-2xl font-bold text-gray-900 mb-2">Report Not Found</h1>
          <p className="text-gray-600 mb-4">{error || 'The requested report could not be found.'}</p>
          <Button onClick={() => window.location.href = '/'}>
            Run New Test
          </Button>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gradient-to-b from-white via-gray-50 to-white flex flex-col">
      <AppHeader variant="app" showBackButton />
      
      <main className="container mx-auto px-4 py-8 pt-24">
        {/* Report Header */}
        <div className="mb-8">
          <h1 className="text-3xl font-bold text-gray-900 mb-2">
            WordPress Audit Report
          </h1>
          <p className="text-gray-600 mb-2">{report.meta.url}</p>
          <p className="text-sm text-gray-500">
            Scanned on {new Date(report.meta.scannedAt).toLocaleDateString()} at {new Date(report.meta.scannedAt).toLocaleTimeString()}
          </p>
        </div>

        {/* Overview Scores Grid */}
        <div className="grid grid-cols-2 md:grid-cols-5 gap-4 mb-8">
          {/* Performance Score */}
          <Card className="border-gray-200">
            <CardContent className="pt-6 text-center">
              <div className="flex items-center justify-center mb-2">
                <Zap className="h-5 w-5 text-gray-700" />
              </div>
              <div className={`text-3xl font-bold mb-1 ${getScoreColor(Math.round((report.performance.scores.mobile + report.performance.scores.desktop) / 2))}`}>
                {Math.round((report.performance.scores.mobile + report.performance.scores.desktop) / 2)}
              </div>
              <div className="text-xs text-gray-600">Performance</div>
            </CardContent>
          </Card>

          {/* SEO Score */}
          <Card className="border-gray-200">
            <CardContent className="pt-6 text-center">
              <div className="flex items-center justify-center mb-2">
                <Eye className="h-5 w-5 text-gray-700" />
              </div>
              <div className={`text-3xl font-bold mb-1 ${getScoreColor(report.seo.score)}`}>
                {report.seo.score}
              </div>
              <div className="text-xs text-gray-600">SEO</div>
            </CardContent>
          </Card>

          {/* Security Score */}
          <Card className="border-gray-200">
            <CardContent className="pt-6 text-center">
              <div className="flex items-center justify-center mb-2">
                <Shield className="h-5 w-5 text-gray-700" />
              </div>
              <div className={`text-3xl font-bold mb-1 ${getScoreColor(report.security.score)}`}>
                {report.security.score}
              </div>
              <div className="text-xs text-gray-600">Security</div>
            </CardContent>
          </Card>

          {/* Accessibility Score */}
          <Card className="border-gray-200">
            <CardContent className="pt-6 text-center">
              <div className="flex items-center justify-center mb-2">
                <Users className="h-5 w-5 text-gray-700" />
              </div>
              <div className={`text-3xl font-bold mb-1 ${getScoreColor(report.accessibility.score)}`}>
                {report.accessibility.score}
              </div>
              <div className="text-xs text-gray-600">Accessibility</div>
            </CardContent>
          </Card>

          {/* GDPR Score */}
          <Card className="border-gray-200">
            <CardContent className="pt-6 text-center">
              <div className="flex items-center justify-center mb-2">
                <Lock className="h-5 w-5 text-gray-700" />
              </div>
              <div className={`text-3xl font-bold mb-1 ${getScoreColor(report.gdpr.score)}`}>
                {report.gdpr.score}
              </div>
              <div className="text-xs text-gray-600">GDPR</div>
            </CardContent>
          </Card>
        </div>

        {/* Performance Section */}
        <Card className="mb-8 border-2 border-gray-200 hover:border-green-400 transition-all duration-300 bg-gradient-to-br from-white to-gray-50 shadow-lg">
          <CardHeader>
            <CardTitle className="flex items-center text-gray-900">
              <div className="h-12 w-12 bg-gradient-to-br from-green-400 to-green-600 rounded-2xl flex items-center justify-center mr-3 shadow-lg">
                <Zap className="h-6 w-6 text-white" />
              </div>
              Performance Analysis
            </CardTitle>
            <CardDescription className="text-gray-600">
              Powered by Google Lighthouse
            </CardDescription>
          </CardHeader>
          <CardContent>
            {/* Mobile and Desktop Scores - Compact 2 Column Layout */}
            <div className="grid md:grid-cols-2 gap-6 mb-8">
              {/* Mobile Score */}
              <div className="bg-white rounded-xl border-2 border-gray-200 p-5 hover:border-green-400 transition-all">
                <div className="flex items-start gap-4">
                  {/* Preview Column */}
                  <div className="flex-shrink-0 w-24">
                    <div className="flex items-center gap-2 mb-2">
                      <Smartphone className="h-4 w-4 text-gray-600" />
                      <span className="text-sm font-semibold text-gray-900">Mobile</span>
                    </div>
                    {report.performance.screenshots?.mobile && (
                      <div className="rounded-lg overflow-hidden border border-gray-200 shadow-sm">
                        <img 
                          src={`http://localhost:3001${report.performance.screenshots.mobile}`}
                          alt="Mobile Preview"
                          className="w-full h-auto"
                        />
                      </div>
                    )}
                  </div>
                  
                  {/* Score Column */}
                  <div className="flex-1 flex flex-col items-center justify-center py-2">
                    <div className={`inline-flex items-center justify-center w-24 h-24 rounded-full border-4 ${getScoreBorderColor(report.performance.scores.mobile)}`}>
                      <div className="text-center">
                        <div className={`text-3xl font-bold ${getScoreColor(report.performance.scores.mobile)}`}>
                          {report.performance.scores.mobile}
                        </div>
                      </div>
                    </div>
                    <Badge className={`mt-3 ${getScoreBadge(report.performance.scores.mobile)}`}>
                      {getScoreLabel(report.performance.scores.mobile)}
                    </Badge>
                  </div>
                </div>
              </div>

              {/* Desktop Score */}
              <div className="bg-white rounded-xl border-2 border-gray-200 p-5 hover:border-blue-400 transition-all">
                <div className="flex items-start gap-4">
                  {/* Preview Column */}
                  <div className="flex-shrink-0 w-24">
                    <div className="flex items-center gap-2 mb-2">
                      <Monitor className="h-4 w-4 text-gray-600" />
                      <span className="text-sm font-semibold text-gray-900">Desktop</span>
                    </div>
                    {report.performance.screenshots?.desktop && (
                      <div className="rounded-lg overflow-hidden border border-gray-200 shadow-sm">
                        <img 
                          src={`http://localhost:3001${report.performance.screenshots.desktop}`}
                          alt="Desktop Preview"
                          className="w-full h-auto"
                        />
                      </div>
                    )}
                  </div>
                  
                  {/* Score Column */}
                  <div className="flex-1 flex flex-col items-center justify-center py-2">
                    <div className={`inline-flex items-center justify-center w-24 h-24 rounded-full border-4 ${getScoreBorderColor(report.performance.scores.desktop)}`}>
                      <div className="text-center">
                        <div className={`text-3xl font-bold ${getScoreColor(report.performance.scores.desktop)}`}>
                          {report.performance.scores.desktop}
                        </div>
                      </div>
                    </div>
                    <Badge className={`mt-3 ${getScoreBadge(report.performance.scores.desktop)}`}>
                      {getScoreLabel(report.performance.scores.desktop)}
                    </Badge>
                  </div>
                </div>
              </div>
            </div>

            {/* Key Summary Table */}
            <div className="bg-white rounded-lg border border-gray-200 overflow-hidden">
              <div className="bg-gray-50 px-6 py-3 border-b border-gray-200">
                <h3 className="text-sm font-semibold text-gray-900 uppercase tracking-wider">Key Summary</h3>
              </div>
              <table className="w-full">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-600 uppercase tracking-wider">Metric</th>
                    <th className="px-6 py-3 text-center text-xs font-medium text-gray-600 uppercase tracking-wider">Value</th>
                    <th className="px-6 py-3 text-center text-xs font-medium text-gray-600 uppercase tracking-wider">Status</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-200">
                  {/* FCP */}
                  <tr className="hover:bg-gray-50">
                    <td className="px-6 py-4">
                      <div className="flex items-center">
                        <Zap className="h-4 w-4 mr-2 text-gray-500" />
                        <span className="font-medium text-gray-900">First Contentful Paint (FCP)</span>
                      </div>
                    </td>
                    <td className="px-6 py-4 text-center text-gray-900 font-semibold">
                      {report.performance.fcp?.toFixed(2) || '0.00'} s
                    </td>
                    <td className="px-6 py-4 text-center">
                      <Badge variant={report.performance.fcp && report.performance.fcp < 1.8 ? 'default' : report.performance.fcp && report.performance.fcp < 3 ? 'secondary' : 'destructive'}>
                        {report.performance.fcp && report.performance.fcp < 1.8 ? 'Good' : report.performance.fcp && report.performance.fcp < 3 ? 'Needs Improvement' : 'Poor'}
                      </Badge>
                    </td>
                  </tr>

                  {/* LCP */}
                  <tr className="hover:bg-gray-50">
                    <td className="px-6 py-4">
                      <div className="flex items-center">
                        <Eye className="h-4 w-4 mr-2 text-gray-500" />
                        <span className="font-medium text-gray-900">Largest Contentful Paint (LCP)</span>
                      </div>
                    </td>
                    <td className="px-6 py-4 text-center text-gray-900 font-semibold">
                      {report.performance.coreWebVitals.lcp.toFixed(2)} s
                    </td>
                    <td className="px-6 py-4 text-center">
                      <Badge variant={report.performance.coreWebVitals.lcp < 2.5 ? 'default' : report.performance.coreWebVitals.lcp < 4 ? 'secondary' : 'destructive'}>
                        {report.performance.coreWebVitals.lcp < 2.5 ? 'Good' : report.performance.coreWebVitals.lcp < 4 ? 'Needs Improvement' : 'Poor'}
                      </Badge>
                    </td>
                  </tr>

                  {/* CLS */}
                  <tr className="hover:bg-gray-50">
                    <td className="px-6 py-4">
                      <div className="flex items-center">
                        <Target className="h-4 w-4 mr-2 text-gray-500" />
                        <span className="font-medium text-gray-900">Cumulative Layout Shift (CLS)</span>
                      </div>
                    </td>
                    <td className="px-6 py-4 text-center text-gray-900 font-semibold">
                      {report.performance.coreWebVitals.cls.toFixed(3)}
                    </td>
                    <td className="px-6 py-4 text-center">
                      <Badge variant={report.performance.coreWebVitals.cls < 0.1 ? 'default' : report.performance.coreWebVitals.cls < 0.25 ? 'secondary' : 'destructive'}>
                        {report.performance.coreWebVitals.cls < 0.1 ? 'Good' : report.performance.coreWebVitals.cls < 0.25 ? 'Needs Improvement' : 'Poor'}
                      </Badge>
                    </td>
                  </tr>

                  {/* TBT */}
                  <tr className="hover:bg-gray-50">
                    <td className="px-6 py-4">
                      <div className="flex items-center">
                        <Clock className="h-4 w-4 mr-2 text-gray-500" />
                        <span className="font-medium text-gray-900">Total Blocking Time (TBT)</span>
                      </div>
                    </td>
                    <td className="px-6 py-4 text-center text-gray-900 font-semibold">
                      {report.performance.tbt || 0} ms
                    </td>
                    <td className="px-6 py-4 text-center">
                      <Badge variant={(report.performance.tbt || 0) < 200 ? 'default' : (report.performance.tbt || 0) < 600 ? 'secondary' : 'destructive'}>
                        {(report.performance.tbt || 0) < 200 ? 'Good' : (report.performance.tbt || 0) < 600 ? 'Needs Improvement' : 'Poor'}
                      </Badge>
                    </td>
                  </tr>

                  {/* Speed Index */}
                  <tr className="hover:bg-gray-50">
                    <td className="px-6 py-4">
                      <div className="flex items-center">
                        <Activity className="h-4 w-4 mr-2 text-gray-500" />
                        <span className="font-medium text-gray-900">Speed Index (SI)</span>
                      </div>
                    </td>
                    <td className="px-6 py-4 text-center text-gray-900 font-semibold">
                      {report.performance.si?.toFixed(2) || '0.00'} s
                    </td>
                    <td className="px-6 py-4 text-center">
                      <Badge variant={report.performance.si && report.performance.si < 3.4 ? 'default' : report.performance.si && report.performance.si < 5.8 ? 'secondary' : 'destructive'}>
                        {report.performance.si && report.performance.si < 3.4 ? 'Good' : report.performance.si && report.performance.si < 5.8 ? 'Needs Improvement' : 'Poor'}
                      </Badge>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </CardContent>
        </Card>

        {/* Optimization Opportunities */}
        {report.performance.opportunities && report.performance.opportunities.length > 0 && (
          <Card className="mb-8 border-2 border-blue-200 bg-gradient-to-br from-blue-50 to-white">
            <CardHeader>
              <CardTitle className="flex items-center text-gray-900">
                <div className="h-10 w-10 bg-blue-600 rounded-lg flex items-center justify-center mr-3">
                  <TrendingUp className="h-5 w-5 text-white" />
                </div>
                Performance Optimization Opportunities
              </CardTitle>
              <CardDescription className="text-gray-600">
                Specific improvements that will boost your performance score
              </CardDescription>
            </CardHeader>
            <CardContent>
              <div className="space-y-4">
                {report.performance.opportunities
                  .sort((a, b) => b.savings.ms - a.savings.ms) // Sort by biggest savings
                  .slice(0, 10) // Top 10
                  .map((opportunity, index) => (
                  <div key={opportunity.id} className="p-4 bg-white border border-gray-200 rounded-lg hover:shadow-md transition-shadow">
                    <div className="flex items-start justify-between mb-2">
                      <div className="flex-1">
                        <div className="flex items-center gap-2 mb-1">
                          <Badge variant="outline" className="text-xs">
                            #{index + 1}
                          </Badge>
                          <h4 className="font-semibold text-gray-900">{opportunity.title}</h4>
                        </div>
                        <p className="text-sm text-gray-600 mb-3">{opportunity.description}</p>
                      </div>
                    </div>

                    <div className="flex items-center gap-4 mb-3">
                      {opportunity.savings.ms > 0 && (
                        <div className="flex items-center gap-2 px-3 py-1 bg-green-50 rounded-md">
                          <Clock className="h-4 w-4 text-green-600" />
                          <span className="text-sm font-semibold text-green-700">
                            {(opportunity.savings.ms / 1000).toFixed(2)}s faster
                          </span>
                        </div>
                      )}
                      {opportunity.savings.bytes > 0 && (
                        <div className="flex items-center gap-2 px-3 py-1 bg-blue-50 rounded-md">
                          <Download className="h-4 w-4 text-blue-600" />
                          <span className="text-sm font-semibold text-blue-700">
                            {(opportunity.savings.bytes / 1024).toFixed(0)} KB saved
                          </span>
                        </div>
                      )}
                    </div>

                    {opportunity.items && opportunity.items.length > 0 && (
                      <details className="mt-3">
                        <summary className="cursor-pointer text-sm text-gray-600 hover:text-gray-900 font-medium">
                          View {opportunity.items.length} affected resource{opportunity.items.length > 1 ? 's' : ''}
                        </summary>
                        <div className="mt-2 pl-4 border-l-2 border-gray-200">
                          {opportunity.items.slice(0, 3).map((item: any, itemIndex: number) => (
                            <div key={itemIndex} className="text-xs text-gray-600 py-1 truncate">
                              {item.url || item.label || JSON.stringify(item).substring(0, 100)}
                            </div>
                          ))}
                          {opportunity.items.length > 3 && (
                            <div className="text-xs text-gray-500 py-1">
                              ...and {opportunity.items.length - 3} more
                            </div>
                          )}
                        </div>
                      </details>
                    )}
                  </div>
                ))}
              </div>

              <div className="mt-6 p-4 bg-gradient-to-r from-blue-50 to-purple-50 rounded-lg border border-blue-200">
                <div className="flex items-start gap-3">
                  <div className="h-10 w-10 bg-blue-600 rounded-lg flex items-center justify-center flex-shrink-0">
                    <Zap className="h-5 w-5 text-white" />
                  </div>
                  <div>
                    <h4 className="font-semibold text-gray-900 mb-1">
                      Estimated Total Improvement
                    </h4>
                    <p className="text-sm text-gray-600 mb-2">
                      By implementing these optimizations, you could save up to{' '}
                      <span className="font-bold text-blue-700">
                        {(report.performance.opportunities.reduce((sum, opp) => sum + opp.savings.ms, 0) / 1000).toFixed(2)}s
                      </span>
                      {' '}in load time and{' '}
                      <span className="font-bold text-blue-700">
                        {(report.performance.opportunities.reduce((sum, opp) => sum + opp.savings.bytes, 0) / 1024 / 1024).toFixed(2)} MB
                      </span>
                      {' '}in page weight.
                    </p>
                    <p className="text-xs text-gray-500">
                      * Estimates based on Google Lighthouse analysis
                    </p>
                  </div>
                </div>
              </div>
            </CardContent>
          </Card>
        )}

        {/* Revenue Loss Calculator */}
        <Card className="mb-8 border-2 border-red-200 bg-gradient-to-br from-red-50 via-orange-50 to-yellow-50">
          <CardHeader>
            <CardTitle className="flex items-center text-gray-900">
              <div className="h-10 w-10 bg-red-600 rounded-lg flex items-center justify-center mr-3">
                <DollarSign className="h-5 w-5 text-white" />
              </div>
              Revenue Impact Calculator
            </CardTitle>
            <CardDescription className="text-gray-700">
              Estimate how much revenue you might be losing due to performance issues
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="grid md:grid-cols-2 gap-8">
              {/* Calculator Inputs */}
              <div className="space-y-6">
                <div>
                  <label className="block text-sm font-semibold text-gray-700 mb-2">
                    Monthly Visitors
                  </label>
                  <input
                    type="number"
                    value={monthlyVisitors}
                    onChange={(e) => setMonthlyVisitors(Number(e.target.value))}
                    className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-red-500 focus:border-transparent"
                    min="0"
                  />
                </div>
                
                <div>
                  <label className="block text-sm font-semibold text-gray-700 mb-2">
                    Conversion Rate (%)
                  </label>
                  <input
                    type="number"
                    value={conversionRate}
                    onChange={(e) => setConversionRate(Number(e.target.value))}
                    className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-red-500 focus:border-transparent"
                    min="0"
                    max="100"
                    step="0.1"
                  />
                </div>
                
                <div>
                  <label className="block text-sm font-semibold text-gray-700 mb-2">
                    Average Order Value ($)
                  </label>
                  <input
                    type="number"
                    value={avgOrderValue}
                    onChange={(e) => setAvgOrderValue(Number(e.target.value))}
                    className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-red-500 focus:border-transparent"
                    min="0"
                  />
                </div>

                <div className="pt-4 border-t border-orange-200">
                  <div className="flex items-start gap-2">
                    <Calculator className="h-5 w-5 text-orange-600 mt-1 flex-shrink-0" />
                    <div>
                      <p className="text-xs text-gray-600 leading-relaxed">
                        Based on your performance score of{' '}
                        <span className="font-semibold">
                          {Math.round((report.performance.scores.mobile + report.performance.scores.desktop) / 2)}
                        </span>{' '}
                        and LCP of{' '}
                        <span className="font-semibold">
                          {report.performance.coreWebVitals.lcp.toFixed(2)}s
                        </span>
                        , we estimate a conversion drop of approximately{' '}
                        <span className="font-semibold text-red-600">
                          {((report.performance.scores.mobile + report.performance.scores.desktop) / 2) < 50 ? '20-30%' : 
                           ((report.performance.scores.mobile + report.performance.scores.desktop) / 2) < 70 ? '12-17%' :
                           ((report.performance.scores.mobile + report.performance.scores.desktop) / 2) < 90 ? '7-12%' : '2-7%'}
                        </span>
                      </p>
                    </div>
                  </div>
                </div>
              </div>

              {/* Results */}
              <div className="space-y-4">
                <div className="bg-white rounded-lg p-6 border-2 border-red-300 shadow-lg">
                  <div className="flex items-center gap-3 mb-4">
                    <div className="h-12 w-12 bg-red-600 rounded-full flex items-center justify-center">
                      <TrendingDown className="h-6 w-6 text-white" />
                    </div>
                    <div>
                      <p className="text-sm text-gray-600">Estimated Monthly Loss</p>
                      <p className="text-3xl font-bold text-red-600">
                        ${revenueLoss.monthly.toLocaleString()}
                      </p>
                    </div>
                  </div>
                  
                  <div className="pt-4 border-t border-gray-200">
                    <p className="text-sm text-gray-600 mb-1">Yearly Impact</p>
                    <p className="text-2xl font-bold text-gray-900">
                      ${revenueLoss.yearly.toLocaleString()}
                    </p>
                  </div>
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div className="bg-white rounded-lg p-4 border border-orange-200">
                    <p className="text-xs text-gray-600 mb-1">Lost Conversions/Month</p>
                    <p className="text-xl font-bold text-orange-700">
                      {revenueLoss.conversionLoss}
                    </p>
                  </div>
                  
                  <div className="bg-white rounded-lg p-4 border border-orange-200">
                    <p className="text-xs text-gray-600 mb-1">Bounce Rate Increase</p>
                    <p className="text-xl font-bold text-orange-700">
                      +{revenueLoss.bounceIncrease}%
                    </p>
                  </div>
                </div>

                <div className="bg-gradient-to-r from-green-50 to-emerald-50 rounded-lg p-4 border border-green-200">
                  <div className="flex items-start gap-3">
                    <Zap className="h-5 w-5 text-green-600 mt-0.5 flex-shrink-0" />
                    <div>
                      <p className="text-sm font-semibold text-gray-900 mb-1">
                        Potential Recovery
                      </p>
                      <p className="text-xs text-gray-700 leading-relaxed">
                        By optimizing your site to reach a 90+ performance score, you could recover up to{' '}
                        <span className="font-bold text-green-700">
                          ${Math.round(revenueLoss.yearly * 0.8).toLocaleString()}/year
                        </span>
                        {' '}in lost revenue.
                      </p>
                    </div>
                  </div>
                </div>

                <div className="text-xs text-gray-500 italic mt-4">
                  * Estimates based on industry research showing that 1-second delay in page load can reduce conversions by 7%. 
                  Actual results may vary based on your specific industry, audience, and site type.
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* WordPress Information */}
        {report.wordpress.isWordPress && (
          <Card className="mb-8 border-gray-200">
            <CardHeader>
              <CardTitle className="flex items-center text-gray-900">
                <div className="h-10 w-10 bg-gray-100 rounded-lg flex items-center justify-center mr-3">
                  <Globe className="h-5 w-5 text-gray-900" />
                </div>
                WordPress Information
              </CardTitle>
              <CardDescription className="text-gray-600">
                WordPress installation details and configuration
              </CardDescription>
            </CardHeader>
            <CardContent>
              <div className="grid md:grid-cols-2 gap-6">
                {/* WordPress Details */}
                <div className="space-y-4">
                  <div className="p-4 bg-gray-50 rounded-lg">
                    <div className="text-sm text-gray-600 mb-1">WordPress Version</div>
                    <div className="text-lg font-semibold text-gray-900">
                      {report.wordpress.version || 'Not detected'}
                    </div>
                  </div>
                  
                  {report.wordpress.theme && (
                    <div className="p-4 bg-gray-50 rounded-lg">
                      <div className="text-sm text-gray-600 mb-1">Active Theme</div>
                      <div className="text-lg font-semibold text-gray-900">
                        {report.wordpress.theme.name}
                        {report.wordpress.theme.child && (
                          <Badge className="ml-2 bg-blue-100 text-blue-700">Child Theme</Badge>
                        )}
                      </div>
                    </div>
                  )}
                </div>

                {/* Plugins */}
                <div>
                  <h4 className="font-semibold text-gray-900 mb-3">Detected Plugins</h4>
                  {report.wordpress.plugins && report.wordpress.plugins.length > 0 ? (
                    <div className="space-y-2">
                      {report.wordpress.plugins.map((plugin, index) => (
                        <div key={index} className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                          <div className="flex items-center">
                            <div className="font-medium text-gray-900">{plugin.slug}</div>
                          </div>
                          <div className="flex items-center gap-2">
                            <Badge variant={plugin.impact === 'high' ? 'destructive' : plugin.impact === 'medium' ? 'secondary' : 'default'}>
                              {plugin.impact} impact
                            </Badge>
                            <span className="text-sm text-gray-500">
                              {Math.round(plugin.confidence * 100)}% confidence
                            </span>
                          </div>
                        </div>
                      ))}
                    </div>
                  ) : (
                    <p className="text-gray-500 text-sm">No plugins detected</p>
                  )}
                </div>
              </div>
            </CardContent>
          </Card>
        )}

        {/* Security Analysis */}
        <Card className="mb-8 border-gray-200">
          <CardHeader>
            <CardTitle className="flex items-center text-gray-900">
              <div className="h-10 w-10 bg-gray-100 rounded-lg flex items-center justify-center mr-3">
                <Shield className="h-5 w-5 text-gray-900" />
              </div>
              Security Analysis
            </CardTitle>
            <CardDescription className="text-gray-600">
              Website security posture and vulnerabilities
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="mb-6">
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-lg font-semibold text-gray-900">Security Score</h3>
                <div className={`text-4xl font-bold ${getScoreColor(report.security.score)}`}>
                  {report.security.score}
                </div>
              </div>
              <div className="w-full bg-gray-200 rounded-full h-2">
                <div 
                  className={`h-2 rounded-full ${report.security.score >= 90 ? 'bg-black' : report.security.score >= 70 ? 'bg-gray-600' : 'bg-gray-400'}`}
                  style={{ width: `${report.security.score}%` }}
                ></div>
              </div>
            </div>

            <div className="grid md:grid-cols-2 gap-6">
              {/* Security Checks */}
              <div>
                <h4 className="font-semibold text-gray-900 mb-3">Security Checks</h4>
                <div className="space-y-2">
                  <div className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                    <span className="text-gray-700">XML-RPC Status</span>
                    <Badge variant={report.security.xmlrpc === 'disabled' ? 'default' : 'destructive'}>
                      {report.security.xmlrpc}
                    </Badge>
                  </div>
                  <div className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                    <span className="text-gray-700">Readme File</span>
                    <Badge variant={report.security.readme === 'not accessible' ? 'default' : 'destructive'}>
                      {report.security.readme}
                    </Badge>
                  </div>
                  <div className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                    <span className="text-gray-700">WP-Config Protection</span>
                    <Badge variant={report.security.wpConfig === 'protected' ? 'default' : 'destructive'}>
                      {report.security.wpConfig}
                    </Badge>
                  </div>
                </div>
              </div>

              {/* Security Headers */}
              <div>
                <h4 className="font-semibold text-gray-900 mb-3">Security Headers</h4>
                <div className="space-y-2">
                  {Object.entries(report.security.headers).map(([key, value]) => (
                    <div key={key} className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                      <span className="text-gray-700 text-sm">
                        {key.replace(/([A-Z])/g, ' $1').trim()}
                      </span>
                      {value ? (
                        <CheckCircle className="h-5 w-5 text-green-600" />
                      ) : (
                        <AlertTriangle className="h-5 w-5 text-red-600" />
                      )}
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* SEO Analysis */}
        <Card className="mb-8 border-gray-200">
          <CardHeader>
            <CardTitle className="flex items-center text-gray-900">
              <div className="h-10 w-10 bg-gray-100 rounded-lg flex items-center justify-center mr-3">
                <Eye className="h-5 w-5 text-gray-900" />
              </div>
              SEO Analysis
            </CardTitle>
            <CardDescription className="text-gray-600">
              Search engine optimization and discoverability
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="mb-6">
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-lg font-semibold text-gray-900">SEO Score</h3>
                <div className={`text-4xl font-bold ${getScoreColor(report.seo.score)}`}>
                  {report.seo.score}
                </div>
              </div>
              <div className="w-full bg-gray-200 rounded-full h-2">
                <div 
                  className={`h-2 rounded-full ${report.seo.score >= 90 ? 'bg-black' : report.seo.score >= 70 ? 'bg-gray-600' : 'bg-gray-400'}`}
                  style={{ width: `${report.seo.score}%` }}
                ></div>
              </div>
            </div>

            <div className="grid md:grid-cols-2 gap-6">
              {/* Basic SEO */}
              <div>
                <h4 className="font-semibold text-gray-900 mb-3">Basic SEO Elements</h4>
                <div className="space-y-2">
                  <div className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                    <div>
                      <div className="font-medium text-gray-900">Title Tag</div>
                      <div className="text-xs text-gray-500">{report.seo.title.length} characters</div>
                    </div>
                    {report.seo.title.present && report.seo.title.optimal ? (
                      <CheckCircle className="h-5 w-5 text-green-600" />
                    ) : (
                      <AlertTriangle className="h-5 w-5 text-yellow-600" />
                    )}
                  </div>
                  <div className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                    <div>
                      <div className="font-medium text-gray-900">Meta Description</div>
                      <div className="text-xs text-gray-500">{report.seo.metaDescription.length} characters</div>
                    </div>
                    {report.seo.metaDescription.present && report.seo.metaDescription.optimal ? (
                      <CheckCircle className="h-5 w-5 text-green-600" />
                    ) : (
                      <AlertTriangle className="h-5 w-5 text-yellow-600" />
                    )}
                  </div>
                  <div className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                    <div>
                      <div className="font-medium text-gray-900">H1 Heading</div>
                      <div className="text-xs text-gray-500">{report.seo.headings.h1Count} found</div>
                    </div>
                    {report.seo.headings.hasSingleH1 ? (
                      <CheckCircle className="h-5 w-5 text-green-600" />
                    ) : (
                      <AlertTriangle className="h-5 w-5 text-yellow-600" />
                    )}
                  </div>
                </div>
              </div>

              {/* Advanced SEO */}
              <div>
                <h4 className="font-semibold text-gray-900 mb-3">Advanced SEO</h4>
                <div className="space-y-2">
                  <div className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                    <span className="text-gray-700">Canonical URL</span>
                    {report.seo.canonical ? (
                      <CheckCircle className="h-5 w-5 text-green-600" />
                    ) : (
                      <AlertTriangle className="h-5 w-5 text-yellow-600" />
                    )}
                  </div>
                  <div className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                    <span className="text-gray-700">Open Graph Tags</span>
                    {report.seo.openGraph.title && report.seo.openGraph.description ? (
                      <CheckCircle className="h-5 w-5 text-green-600" />
                    ) : (
                      <AlertTriangle className="h-5 w-5 text-yellow-600" />
                    )}
                  </div>
                  <div className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                    <span className="text-gray-700">Twitter Cards</span>
                    {report.seo.twitterCard ? (
                      <CheckCircle className="h-5 w-5 text-green-600" />
                    ) : (
                      <AlertTriangle className="h-5 w-5 text-yellow-600" />
                    )}
                  </div>
                  <div className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                    <span className="text-gray-700">Structured Data</span>
                    <Badge>{report.seo.schemas.length} schemas</Badge>
                  </div>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Accessibility Analysis */}
        <Card className="mb-8 border-gray-200">
          <CardHeader>
            <CardTitle className="flex items-center text-gray-900">
              <div className="h-10 w-10 bg-gray-100 rounded-lg flex items-center justify-center mr-3">
                <Users className="h-5 w-5 text-gray-900" />
              </div>
              Accessibility Analysis
            </CardTitle>
            <CardDescription className="text-gray-600">
              Website accessibility for all users
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="mb-6">
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-lg font-semibold text-gray-900">Accessibility Score</h3>
                <div className={`text-4xl font-bold ${getScoreColor(report.accessibility.score)}`}>
                  {report.accessibility.score}
                </div>
              </div>
              <div className="w-full bg-gray-200 rounded-full h-2">
                <div 
                  className={`h-2 rounded-full ${report.accessibility.score >= 90 ? 'bg-black' : report.accessibility.score >= 70 ? 'bg-gray-600' : 'bg-gray-400'}`}
                  style={{ width: `${report.accessibility.score}%` }}
                ></div>
              </div>
            </div>

            <div className="grid md:grid-cols-2 gap-6">
              <div className="p-4 bg-gray-50 rounded-lg">
                <div className="text-sm text-gray-600 mb-2">Language Attribute</div>
                <div className="flex items-center justify-between">
                  <span className="font-medium text-gray-900">{report.accessibility.lang ? 'Present' : 'Missing'}</span>
                  {report.accessibility.lang ? (
                    <CheckCircle className="h-5 w-5 text-green-600" />
                  ) : (
                    <AlertTriangle className="h-5 w-5 text-red-600" />
                  )}
                </div>
              </div>

              <div className="p-4 bg-gray-50 rounded-lg">
                <div className="text-sm text-gray-600 mb-2">Image Alt Text</div>
                <div className="flex items-center justify-between">
                  <span className="font-medium text-gray-900">
                    {report.accessibility.images.altPercentage.toFixed(0)}% coverage
                  </span>
                  <span className="text-sm text-gray-500">
                    {report.accessibility.images.total - report.accessibility.images.withoutAlt}/{report.accessibility.images.total}
                  </span>
                </div>
              </div>

              <div className="p-4 bg-gray-50 rounded-lg">
                <div className="text-sm text-gray-600 mb-2">Form Labels</div>
                <div className="flex items-center justify-between">
                  <span className="font-medium text-gray-900">
                    {report.accessibility.forms.labelPercentage.toFixed(0)}% labeled
                  </span>
                  <span className="text-sm text-gray-500">
                    {report.accessibility.forms.withLabels}/{report.accessibility.forms.total}
                  </span>
                </div>
              </div>

              <div className="p-4 bg-gray-50 rounded-lg">
                <div className="text-sm text-gray-600 mb-2">Color Contrast</div>
                <div className="flex items-center justify-between">
                  <span className="font-medium text-gray-900">{report.accessibility.contrast ? 'Good' : 'Needs Review'}</span>
                  {report.accessibility.contrast ? (
                    <CheckCircle className="h-5 w-5 text-green-600" />
                  ) : (
                    <AlertTriangle className="h-5 w-5 text-yellow-600" />
                  )}
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* GDPR Compliance */}
        <Card className="mb-8 border-gray-200">
          <CardHeader>
            <CardTitle className="flex items-center text-gray-900">
              <div className="h-10 w-10 bg-gray-100 rounded-lg flex items-center justify-center mr-3">
                <Lock className="h-5 w-5 text-gray-900" />
              </div>
              GDPR Compliance
            </CardTitle>
            <CardDescription className="text-gray-600">
              Privacy and data protection compliance
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="mb-6">
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-lg font-semibold text-gray-900">GDPR Score</h3>
                <div className={`text-4xl font-bold ${getScoreColor(report.gdpr.score)}`}>
                  {report.gdpr.score}
                </div>
              </div>
              <div className="w-full bg-gray-200 rounded-full h-2">
                <div 
                  className={`h-2 rounded-full ${report.gdpr.score >= 90 ? 'bg-black' : report.gdpr.score >= 70 ? 'bg-gray-600' : 'bg-gray-400'}`}
                  style={{ width: `${report.gdpr.score}%` }}
                ></div>
              </div>
            </div>

            <div className="grid md:grid-cols-2 gap-4">
              <div className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                <span className="text-gray-700">Privacy Policy</span>
                {report.gdpr.privacyPolicy ? (
                  <CheckCircle className="h-5 w-5 text-green-600" />
                ) : (
                  <AlertTriangle className="h-5 w-5 text-red-600" />
                )}
              </div>
              <div className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                <span className="text-gray-700">Cookie Notice</span>
                {report.gdpr.cookieNotice ? (
                  <CheckCircle className="h-5 w-5 text-green-600" />
                ) : (
                  <AlertTriangle className="h-5 w-5 text-red-600" />
                )}
              </div>
              <div className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                <span className="text-gray-700">Contact Information</span>
                {report.gdpr.contactInfo ? (
                  <CheckCircle className="h-5 w-5 text-green-600" />
                ) : (
                  <AlertTriangle className="h-5 w-5 text-red-600" />
                )}
              </div>
              <div className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                <span className="text-gray-700">Imprint/Legal Notice</span>
                {report.gdpr.imprint ? (
                  <CheckCircle className="h-5 w-5 text-green-600" />
                ) : (
                  <AlertTriangle className="h-5 w-5 text-yellow-600" />
                )}
              </div>
            </div>

            {report.gdpr.tracking.present && (
              <div className="mt-6 p-4 bg-blue-50 rounded-lg border border-blue-200">
                <h4 className="font-semibold text-gray-900 mb-2">Tracking Scripts Detected</h4>
                <div className="flex items-center gap-2">
                  <Badge variant="secondary">{report.gdpr.tracking.scripts} tracking script{report.gdpr.tracking.scripts !== 1 ? 's' : ''}</Badge>
                </div>
              </div>
            )}
          </CardContent>
        </Card>

        {/* Share Your Results */}
        <Card className="mb-8 border-2 border-gray-800 bg-gradient-to-br from-gray-50 to-white">
          <CardContent className="pt-6">
            <div className="text-center">
              <div className="flex items-center justify-center mb-4">
                <div className="h-12 w-12 bg-gray-900 rounded-full flex items-center justify-center">
                  <Share2 className="h-6 w-6 text-white" />
                </div>
              </div>
              <h3 className="text-2xl font-bold text-gray-900 mb-2">
                Share Your Audit Results
              </h3>
              <p className="text-gray-600 mb-6 max-w-2xl mx-auto">
                Help others improve their WordPress sites. Share your results on social media and show the world how your site performs.
              </p>
              
              <div className="flex items-center justify-center gap-3 flex-wrap">
                <Button 
                  size="lg"
                  onClick={copyLink}
                  className="bg-gray-900 hover:bg-gray-800 text-white"
                >
                  {copied ? (
                    <>
                      <CheckCircle className="h-5 w-5 mr-2" />
                      Link Copied!
                    </>
                  ) : (
                    <>
                      <Copy className="h-5 w-5 mr-2" />
                      Copy Share Link
                    </>
                  )}
                </Button>
                
                <Button 
                  size="lg"
                  variant="outline"
                  onClick={shareOnTwitter}
                  className="border-gray-300"
                >
                  <Twitter className="h-5 w-5 mr-2" />
                  Share on Twitter
                </Button>
                
                <Button 
                  size="lg"
                  variant="outline"
                  onClick={shareOnLinkedIn}
                  className="border-gray-300"
                >
                  <Linkedin className="h-5 w-5 mr-2" />
                  Share on LinkedIn
                </Button>
              </div>

              {/* Badge for Website */}
              <div className="mt-8 pt-6 border-t border-gray-200">
                <p className="text-sm text-gray-600 mb-3">Add this badge to your website:</p>
                <div className="bg-gray-100 rounded-lg p-4 max-w-2xl mx-auto">
                  <code className="text-xs text-gray-800 break-all">
                    {`<a href="${shareUrl}" target="_blank" rel="noopener">
  <img src="https://img.shields.io/badge/Audited_by-Just_Audit_It-black?style=for-the-badge&logo=wordpress" alt="Audited by Just Audit It" />
</a>`}
                  </code>
                  <Button 
                    size="sm" 
                    variant="ghost"
                    onClick={async () => {
                      await navigator.clipboard.writeText(`<a href="${shareUrl}" target="_blank" rel="noopener"><img src="https://img.shields.io/badge/Audited_by-Just_Audit_It-black?style=for-the-badge&logo=wordpress" alt="Audited by Just Audit It" /></a>`)
                      setCopied(true)
                      setTimeout(() => setCopied(false), 2000)
                    }}
                    className="mt-2"
                  >
                    <Copy className="h-3 w-3 mr-1" />
                    Copy Badge Code
                  </Button>
                </div>
                <div className="mt-3">
                  <img 
                    src="https://img.shields.io/badge/Audited_by-Just_Audit_It-black?style=for-the-badge&logo=wordpress" 
                    alt="Audited by Just Audit It Badge"
                    className="mx-auto"
                  />
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Core Web Vitals - Detailed Metrics */}
        <Card className="mb-8 border-gray-200">
          <CardHeader>
            <CardTitle className="flex items-center text-gray-900">
              <div className="h-10 w-10 bg-gray-100 rounded-lg flex items-center justify-center mr-3">
                <Activity className="h-5 w-5 text-gray-900" />
              </div>
              Core Web Vitals & Performance Metrics
            </CardTitle>
            <CardDescription className="text-gray-600">
              Google's key metrics for user experience and performance
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6">
              {/* Core Web Vitals */}
              <div className="space-y-4">
                <h4 className="font-semibold text-lg text-gray-900">Core Web Vitals</h4>
                <div className="space-y-3">
                  <div className="flex justify-between items-center p-3 bg-gray-50 rounded-lg">
                    <div>
                      <div className="font-medium">LCP</div>
                      <div className="text-sm text-gray-500">Largest Contentful Paint</div>
                    </div>
                    <div className={`text-lg font-bold ${report.performance.coreWebVitals.lcp <= 2.5 ? 'text-green-600' : 'text-red-600'}`}>
                      {report.performance.coreWebVitals.lcp.toFixed(1)}s
                    </div>
                  </div>
                  <div className="flex justify-between items-center p-3 bg-gray-50 rounded-lg">
                    <div>
                      <div className="font-medium">CLS</div>
                      <div className="text-sm text-gray-500">Cumulative Layout Shift</div>
                    </div>
                    <div className={`text-lg font-bold ${report.performance.coreWebVitals.cls <= 0.1 ? 'text-green-600' : 'text-red-600'}`}>
                      {report.performance.coreWebVitals.cls.toFixed(3)}
                    </div>
                  </div>
                  <div className="flex justify-between items-center p-3 bg-gray-50 rounded-lg">
                    <div>
                      <div className="font-medium">INP</div>
                      <div className="text-sm text-gray-500">Interaction to Next Paint</div>
                    </div>
                    <div className={`text-lg font-bold ${report.performance.coreWebVitals.inp <= 200 ? 'text-green-600' : 'text-red-600'}`}>
                      {report.performance.coreWebVitals.inp.toFixed(0)}ms
                    </div>
                  </div>
                </div>
              </div>

              {/* Additional Performance Metrics */}
              <div className="space-y-4">
                <h4 className="font-semibold text-lg text-gray-900">Performance Metrics</h4>
                <div className="space-y-3">
                  {report.performance.fcp && (
                    <div className="flex justify-between items-center p-3 bg-gray-50 rounded-lg">
                      <div>
                        <div className="font-medium">FCP</div>
                        <div className="text-sm text-gray-500">First Contentful Paint</div>
                      </div>
                      <div className={`text-lg font-bold ${report.performance.fcp <= 1.8 ? 'text-green-600' : 'text-red-600'}`}>
                        {report.performance.fcp.toFixed(1)}s
                      </div>
                    </div>
                  )}
                  {report.performance.ttfb && (
                    <div className="flex justify-between items-center p-3 bg-gray-50 rounded-lg">
                      <div>
                        <div className="font-medium">TTFB</div>
                        <div className="text-sm text-gray-500">Time to First Byte</div>
                      </div>
                      <div className={`text-lg font-bold ${report.performance.ttfb <= 600 ? 'text-green-600' : 'text-red-600'}`}>
                        {report.performance.ttfb.toFixed(0)}ms
                      </div>
                    </div>
                  )}
                  <div className="flex justify-between items-center p-3 bg-gray-50 rounded-lg">
                    <div>
                      <div className="font-medium">Requests</div>
                      <div className="text-sm text-gray-500">Total HTTP Requests</div>
                    </div>
                    <div className="text-lg font-bold text-gray-700">
                      {report.performance.requests}
                    </div>
                  </div>
                </div>
              </div>

              {/* Resource Analysis */}
              <div className="space-y-4">
                <h4 className="font-semibold text-lg text-gray-900">Resource Analysis</h4>
                <div className="space-y-3">
                  <div className="flex justify-between items-center p-3 bg-gray-50 rounded-lg">
                    <div>
                      <div className="font-medium">Page Size</div>
                      <div className="text-sm text-gray-500">Total Transfer Size</div>
                    </div>
                    <div className="text-lg font-bold text-gray-700">
                      {report.performance.transferMB.toFixed(2)} MB
                    </div>
                  </div>
                  {report.performance.imageSize && (
                    <div className="flex justify-between items-center p-3 bg-gray-50 rounded-lg">
                      <div>
                        <div className="font-medium">Images</div>
                        <div className="text-sm text-gray-500">Image Resources</div>
                      </div>
                      <div className="text-lg font-bold text-gray-700">
                        {report.performance.imageSize.toFixed(2)} MB
                      </div>
                    </div>
                  )}
                  {report.performance.scriptSize && (
                    <div className="flex justify-between items-center p-3 bg-gray-50 rounded-lg">
                      <div>
                        <div className="font-medium">Scripts</div>
                        <div className="text-sm text-gray-500">JavaScript Files</div>
                      </div>
                      <div className="text-lg font-bold text-gray-700">
                        {report.performance.scriptSize.toFixed(2)} MB
                      </div>
                    </div>
                  )}
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* SEO Analysis */}
        <Card className="mb-8 border-gray-200">
          <CardHeader>
            <CardTitle className="flex items-center text-gray-900">
              <div className="h-10 w-10 bg-gray-100 rounded-lg flex items-center justify-center mr-3">
                <Eye className="h-5 w-5 text-gray-900" />
              </div>
              SEO Analysis
            </CardTitle>
            <CardDescription className="text-gray-600">
              Search engine optimization factors
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="grid md:grid-cols-2 gap-6">
              <div>
                <div className="flex items-center justify-between mb-4">
                  <h4 className="font-semibold">SEO Score</h4>
                  <Badge className={getScoreBadge(report.seo.score)}>
                    {report.seo.score}/100
                  </Badge>
                </div>
                <div className="space-y-3">
                  <div className="flex justify-between">
                    <span>Title Tag</span>
                    <Badge variant={report.seo.title.present ? "default" : "destructive"}>
                      {report.seo.title.present ? "Present" : "Missing"} ({report.seo.title.length} chars)
                    </Badge>
                  </div>
                  <div className="flex justify-between">
                    <span>Meta Description</span>
                    <Badge variant={report.seo.metaDescription.present ? "default" : "destructive"}>
                      {report.seo.metaDescription.present ? "Present" : "Missing"} ({report.seo.metaDescription.length} chars)
                    </Badge>
                  </div>
                  <div className="flex justify-between">
                    <span>H1 Tags</span>
                    <Badge variant={report.seo.headings.hasSingleH1 ? "default" : "destructive"}>
                      {report.seo.headings.h1Count} ({report.seo.headings.hasSingleH1 ? "Good" : "Issues"})
                    </Badge>
                  </div>
                </div>
              </div>
              <div>
                <h4 className="font-semibold mb-3">Social Media</h4>
                <div className="space-y-2">
                  <div className="flex justify-between">
                    <span>Open Graph</span>
                    <Badge variant={report.seo.openGraph.title && report.seo.openGraph.description ? "default" : "destructive"}>
                      {report.seo.openGraph.title && report.seo.openGraph.description ? "Complete" : "Incomplete"}
                    </Badge>
                  </div>
                  <div className="flex justify-between">
                    <span>Twitter Cards</span>
                    <Badge variant={report.seo.twitterCard ? "default" : "destructive"}>
                      {report.seo.twitterCard ? "Present" : "Missing"}
                    </Badge>
                  </div>
                  <div className="flex justify-between">
                    <span>Schema.org</span>
                    <Badge variant={report.seo.schemas.length > 0 ? "default" : "destructive"}>
                      {report.seo.schemas.length} schemas
                    </Badge>
                  </div>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Security Analysis */}
        <Card className="mb-8 border-gray-200">
          <CardHeader>
            <CardTitle className="flex items-center text-gray-900">
              <div className="h-10 w-10 bg-gray-100 rounded-lg flex items-center justify-center mr-3">
                <Shield className="h-5 w-5 text-gray-900" />
              </div>
              Security Analysis
            </CardTitle>
            <CardDescription className="text-gray-600">
              WordPress security vulnerabilities and best practices
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="grid md:grid-cols-2 gap-6">
              <div>
                <div className="flex items-center justify-between mb-4">
                  <h4 className="font-semibold">Security Score</h4>
                  <Badge className={getScoreBadge(report.security.score)}>
                    {report.security.score}/100
                  </Badge>
                </div>
                <div className="space-y-3">
                  <div className="flex justify-between">
                    <span>XML-RPC</span>
                    <Badge variant={report.security.xmlrpc === 'protected' ? "default" : "destructive"}>
                      {report.security.xmlrpc === 'protected' ? "✅ Protected" : "⚠️ Open"}
                    </Badge>
                  </div>
                  <div className="flex justify-between">
                    <span>Readme.html</span>
                    <Badge variant={report.security.readme === 'protected' ? "default" : "destructive"}>
                      {report.security.readme === 'protected' ? "✅ Protected" : "⚠️ Accessible"}
                    </Badge>
                  </div>
                  <div className="flex justify-between">
                    <span>wp-config.php</span>
                    <Badge variant={report.security.wpConfig === 'protected' ? "default" : "destructive"}>
                      {report.security.wpConfig === 'protected' ? "✅ Protected" : "⚠️ Accessible"}
                    </Badge>
                  </div>
                </div>
              </div>
              <div>
                <h4 className="font-semibold mb-3">Security Headers</h4>
                <div className="space-y-2">
                  {Object.entries(report.security.headers).map(([header, present]) => (
                    <div key={header} className="flex justify-between">
                      <span className="capitalize">{header.replace(/([A-Z])/g, ' $1').trim()}</span>
                      <Badge variant={present ? "default" : "destructive"}>
                        {present ? "✅ Present" : "❌ Missing"}
                      </Badge>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Accessibility Analysis */}
        <Card className="mb-8 border-gray-200">
          <CardHeader>
            <CardTitle className="flex items-center text-gray-900">
              <div className="h-10 w-10 bg-gray-100 rounded-lg flex items-center justify-center mr-3">
                <Users className="h-5 w-5 text-gray-900" />
              </div>
              Accessibility Analysis
            </CardTitle>
            <CardDescription className="text-gray-600">
              Web accessibility compliance and best practices
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="grid md:grid-cols-2 gap-6">
              <div>
                <div className="flex items-center justify-between mb-4">
                  <h4 className="font-semibold">Accessibility Score</h4>
                  <Badge className={getScoreBadge(report.accessibility.score)}>
                    {report.accessibility.score}/100
                  </Badge>
                </div>
                <div className="space-y-3">
                  <div className="flex justify-between">
                    <span>Language Attribute</span>
                    <Badge variant={report.accessibility.lang ? "default" : "destructive"}>
                      {report.accessibility.lang ? "✅ Present" : "❌ Missing"}
                    </Badge>
                  </div>
                  <div className="flex justify-between">
                    <span>Image Alt Text</span>
                    <Badge variant={report.accessibility.images.altPercentage >= 90 ? "default" : "destructive"}>
                      {report.accessibility.images.altPercentage}%
                    </Badge>
                  </div>
                  <div className="flex justify-between">
                    <span>Form Labels</span>
                    <Badge variant={report.accessibility.forms.labelPercentage >= 80 ? "default" : "destructive"}>
                      {report.accessibility.forms.labelPercentage}%
                    </Badge>
                  </div>
                </div>
              </div>
              <div>
                <h4 className="font-semibold mb-3">Accessibility Details</h4>
                <div className="space-y-2">
                  <div className="flex justify-between">
                    <span>Total Images</span>
                    <span className="text-gray-600">{report.accessibility.images.total}</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Images without Alt</span>
                    <span className="text-gray-600">{report.accessibility.images.withoutAlt}</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Form Inputs</span>
                    <span className="text-gray-600">{report.accessibility.forms.total}</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Color Contrast</span>
                    <Badge variant={report.accessibility.contrast ? "default" : "destructive"}>
                      {report.accessibility.contrast ? "✅ Good" : "❌ Poor"}
                    </Badge>
                  </div>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* GDPR Compliance */}
        {report.gdpr && (
          <Card className="mb-8 border-gray-200">
            <CardHeader>
              <CardTitle className="flex items-center text-gray-900">
                <div className="h-10 w-10 bg-gray-100 rounded-lg flex items-center justify-center mr-3">
                  <Globe className="h-5 w-5 text-gray-900" />
                </div>
                GDPR Compliance
              </CardTitle>
              <CardDescription className="text-gray-600">
                European Union General Data Protection Regulation compliance
              </CardDescription>
            </CardHeader>
            <CardContent>
              <div className="grid md:grid-cols-2 gap-6">
                <div>
                  <h4 className="font-semibold mb-3">Compliance Status</h4>
                  <div className="space-y-2">
                    <div className="flex justify-between">
                      <span>Privacy Policy</span>
                      <Badge variant={report.gdpr.privacyPolicy ? "default" : "destructive"}>
                        {report.gdpr.privacyPolicy ? "✅ Present" : "❌ Missing"}
                      </Badge>
                    </div>
                    <div className="flex justify-between">
                      <span>Cookie Notice</span>
                      <Badge variant={report.gdpr.cookieNotice ? "default" : "destructive"}>
                        {report.gdpr.cookieNotice ? "✅ Present" : "❌ Missing"}
                      </Badge>
                    </div>
                    <div className="flex justify-between">
                      <span>Contact Information</span>
                      <Badge variant={report.gdpr.contactInfo ? "default" : "destructive"}>
                        {report.gdpr.contactInfo ? "✅ Present" : "❌ Missing"}
                      </Badge>
                    </div>
                  </div>
                </div>
                <div>
                  <h4 className="font-semibold mb-3">Tracking Analysis</h4>
                  <div className="space-y-2">
                    <div className="flex justify-between">
                      <span>Tracking Scripts</span>
                      <Badge variant={report.gdpr.tracking.present ? "destructive" : "default"}>
                        {report.gdpr.tracking.scripts} detected
                      </Badge>
                    </div>
                    <div className="flex justify-between">
                      <span>GDPR Score</span>
                      <Badge className={getScoreBadge(report.gdpr.score)}>
                        {report.gdpr.score}/100
                      </Badge>
                    </div>
                  </div>
                </div>
              </div>
            </CardContent>
          </Card>
        )}

        {/* WordPress Information */}
        <Card className="mb-8 border-gray-200">
          <CardHeader>
            <CardTitle className="flex items-center text-gray-900">
              <div className="h-10 w-10 bg-gray-100 rounded-lg flex items-center justify-center mr-3">
                <Target className="h-5 w-5 text-gray-900" />
              </div>
              WordPress Information
            </CardTitle>
            <CardDescription className="text-gray-600">
              Detected WordPress installation details
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="grid md:grid-cols-2 gap-6">
              <div>
                <h4 className="font-semibold mb-3">Site Information</h4>
                <div className="space-y-2">
                  <div className="flex justify-between">
                    <span>WordPress Version</span>
                    <Badge variant={report.wordpress.version ? "default" : "secondary"}>
                      {report.wordpress.version || 'Not detected'}
                    </Badge>
                  </div>
                  <div className="flex justify-between">
                    <span>Active Theme</span>
                    <Badge variant={report.wordpress.theme ? "default" : "secondary"}>
                      {report.wordpress.theme?.name || 'Not detected'}
                    </Badge>
                  </div>
                  <div className="flex justify-between">
                    <span>Child Theme</span>
                    <Badge variant={report.wordpress.theme?.child ? "default" : "secondary"}>
                      {report.wordpress.theme?.child ? "Yes" : "No"}
                    </Badge>
                  </div>
                </div>
              </div>
              <div>
                <h4 className="font-semibold mb-3">Detected Plugins</h4>
                <div className="space-y-2">
                  {report.wordpress.plugins?.map((plugin, index) => (
                    <div key={index} className="flex justify-between">
                      <span className="capitalize">{plugin.slug}</span>
                      <div className="flex space-x-2">
                        <Badge className={getImpactBadge(plugin.impact)}>
                          {plugin.impact}
                        </Badge>
                        <Badge variant="outline">
                          {Math.round(plugin.confidence * 100)}%
                        </Badge>
                      </div>
                    </div>
                  )) || <span className="text-gray-500">No plugins detected</span>}
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Recommendations */}
        <Card className="mb-8 border-gray-200">
          <CardHeader>
            <CardTitle className="flex items-center text-gray-900">
              <div className="h-10 w-10 bg-gray-100 rounded-lg flex items-center justify-center mr-3">
                <TrendingUp className="h-5 w-5 text-gray-900" />
              </div>
              Recommended Actions
            </CardTitle>
            <CardDescription className="text-gray-600">
              Priority-based recommendations for improvement
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              {report.priorities.map((priority, index) => (
                <div key={index} className="p-4 border rounded-lg">
                  <div className="flex items-start justify-between mb-2">
                    <h4 className="font-semibold text-lg">{priority.title}</h4>
                    <div className="flex space-x-2">
                      <Badge className={getImpactBadge(priority.impact)}>
                        {priority.impact} impact
                      </Badge>
                      <Badge variant="outline">
                        {priority.effort} effort
                      </Badge>
                    </div>
                  </div>
                  <p className="text-gray-600">{priority.why}</p>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>

        {/* Estimation */}
        <Card className="mb-8 border-gray-200">
          <CardHeader>
            <CardTitle className="flex items-center text-gray-900">
              <div className="h-10 w-10 bg-gray-100 rounded-lg flex items-center justify-center mr-3">
                <Clock className="h-5 w-5 text-gray-900" />
              </div>
              Implementation Estimate
            </CardTitle>
            <CardDescription className="text-gray-600">
              Estimated time and recommended service package
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="grid md:grid-cols-2 gap-6">
              <div className="p-6 bg-gray-50 rounded-lg border border-gray-100">
                <h4 className="font-semibold mb-3 text-gray-900">Time Estimate</h4>
                <div className="text-4xl font-bold text-gray-900 mb-2">
                  {report.estimation.hours} hours
                </div>
                <p className="text-gray-600">
                  Based on the complexity and number of issues found
                </p>
              </div>
              <div className="p-6 bg-gray-50 rounded-lg border border-gray-100">
                <h4 className="font-semibold mb-3 text-gray-900">Recommended Package</h4>
                <Badge className="bg-black text-white text-lg px-4 py-2">
                  {report.estimation.bundle}
                </Badge>
                <p className="text-gray-600 mt-2">
                  Best suited for your website's needs
                </p>
              </div>
            </div>
          </CardContent>
        </Card>
      </main>

      <AppFooter />
    </div>
  )
}