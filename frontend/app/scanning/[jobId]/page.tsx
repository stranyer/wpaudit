'use client'

import { useState, useEffect } from 'react'
import { useParams } from 'next/navigation'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { 
  Zap, 
  Globe, 
  Activity, 
  Brain,
  CheckCircle,
  Clock,
  Loader2,
  Lightbulb,
  Shield,
  Search,
  AlertTriangle
} from 'lucide-react'

interface ScanStatus {
  jobId: string
  status: 'queued' | 'running' | 'completed' | 'failed'
  progress: number
  message: string
  result?: {
    id: string
    publicId: string
    data: any
  }
}

const funFacts = [
  { icon: Zap, text: "A 1-second delay in page load time can reduce conversions by 7%", source: "Google Research" },
  { icon: Activity, text: "53% of mobile users abandon sites that take longer than 3 seconds to load", source: "Google/SOASTA" },
  { icon: Shield, text: "WordPress powers 43% of all websites on the internet", source: "W3Techs" },
  { icon: Search, text: "Page speed is a direct ranking factor for Google search results", source: "Google" },
  { icon: Lightbulb, text: "Optimizing images can reduce page weight by 50-80% on average", source: "HTTP Archive" },
  { icon: Zap, text: "Amazon found that every 100ms delay costs them 1% in sales", source: "Amazon" },
  { icon: Activity, text: "The average webpage is now over 2MB in size", source: "HTTP Archive 2024" },
  { icon: Shield, text: "80% of WordPress vulnerabilities come from plugins", source: "WPScan" },
  { icon: Search, text: "Google uses over 200 ranking factors in their algorithm", source: "Google" },
  { icon: Lightbulb, text: "Lazy loading images can improve initial page load by 50%", source: "Web.dev" }
]

export default function ScanningPage() {
  const params = useParams()
  const [scanStatus, setScanStatus] = useState<ScanStatus | null>(null)
  const [currentStep, setCurrentStep] = useState(0)
  const [timeRemaining, setTimeRemaining] = useState(60)
  const [elapsedTime, setElapsedTime] = useState(0)
  const [currentFactIndex, setCurrentFactIndex] = useState(0)

  const steps = [
    { id: 'scanning', label: 'SCANNING WEBSITE', icon: Globe, description: 'Connecting and analyzing your website...' },
    { id: 'speed', label: 'SPEED ANALYSIS', icon: Activity, description: 'Testing performance with Google PageSpeed Insights...' },
    { id: 'ai', label: 'AI SCORE PREDICTION', icon: Brain, description: 'Analyzing potential performance improvements...' },
    { id: 'report', label: 'AI REPORT', icon: Zap, description: 'Generating comprehensive audit report...' }
  ]

  useEffect(() => {
    if (!params.jobId) return

    const pollStatus = async () => {
      try {
        const response = await fetch(`/api/scan/${params.jobId}`)
        const data = await response.json()
        
        console.log('Scan status:', data)
        setScanStatus(data)

        // Update current step based on progress
        if (data.progress < 25) setCurrentStep(0)
        else if (data.progress < 50) setCurrentStep(1)
        else if (data.progress < 75) setCurrentStep(2)
        else if (data.progress < 100) setCurrentStep(3)
        else setCurrentStep(4)

        // Redirect when completed
        if (data.status === 'completed' && data.result?.id) {
          setTimeout(() => {
            window.location.href = `/report/${data.result.id}`
          }, 2000)
        }

        // Continue polling if not completed
        if (data.status !== 'completed' && data.status !== 'failed') {
          setTimeout(pollStatus, 2000)
        }
      } catch (error) {
        console.error('Error polling scan status:', error)
      }
    }

    // Start polling
    pollStatus()

    // Countdown timer and elapsed timer
    const timer = setInterval(() => {
      setTimeRemaining(prev => {
        if (prev <= 1) {
          clearInterval(timer)
          return 0
        }
        return prev - 1
      })
      setElapsedTime(prev => prev + 1)
    }, 1000)

    // Rotate fun facts every 6 seconds
    const factTimer = setInterval(() => {
      setCurrentFactIndex(prev => (prev + 1) % funFacts.length)
    }, 6000)

    return () => {
      clearInterval(timer)
      clearInterval(factTimer)
    }
  }, [params.jobId])

  const getStepStatus = (stepIndex: number) => {
    if (stepIndex < currentStep) return 'completed'
    if (stepIndex === currentStep) return 'active'
    return 'pending'
  }

  const getStepIcon = (stepIndex: number, Icon: any) => {
    const status = getStepStatus(stepIndex)
    
    if (status === 'completed') {
      return <CheckCircle className="h-6 w-6 text-white" />
    } else if (status === 'active') {
      return <Loader2 className="h-6 w-6 text-black animate-spin" />
    } else {
      return <Icon className="h-6 w-6 text-gray-400" />
    }
  }

  const getSubTask = () => {
    const progress = scanStatus?.progress || 0
    
    if (progress < 10) return "Connecting to website..."
    if (progress < 20) return "Analyzing page structure and HTML..."
    if (progress < 30) return "Detecting WordPress installation..."
    if (progress < 35) return "Identifying theme and plugins..."
    if (progress < 40) return "Checking security headers..."
    if (progress < 45) return "Starting performance analysis..."
    if (progress < 60) return "Running mobile Lighthouse audit..."
    if (progress < 75) return "Running desktop Lighthouse audit..."
    if (progress < 80) return "Analyzing SEO factors..."
    if (progress < 85) return "Checking accessibility..."
    if (progress < 90) return "Verifying GDPR compliance..."
    if (progress < 95) return "Generating report..."
    return "Finalizing results..."
  }

  return (
    <div className="min-h-screen bg-white flex items-center justify-center p-4">
      <div className="w-full max-w-4xl">
        {/* Header */}
        <div className="text-center mb-12">
          <div className="flex items-center justify-center mb-6">
            <div className="h-12 w-12 bg-black rounded-md flex items-center justify-center">
              <Zap className="h-6 w-6 text-white" />
            </div>
          </div>
          <h1 className="text-4xl font-bold text-gray-900 mb-3">Analyzing Your Site</h1>
          <p className="text-lg text-gray-600">Running comprehensive audit powered by Google Lighthouse</p>
        </div>

        {/* Progress Steps */}
        <Card className="mb-8 border-gray-200">
          <CardContent className="p-8">
            <div className="flex items-center justify-between mb-8">
              {steps.map((step, index) => (
                <div key={step.id} className="flex flex-col items-center flex-1 relative">
                  <div className="flex items-center justify-center w-14 h-14 rounded-lg border-2 mb-4 transition-all duration-300"
                       style={{
                         borderColor: getStepStatus(index) === 'completed' ? '#000' : 
                                     getStepStatus(index) === 'active' ? '#000' : '#e5e7eb',
                         backgroundColor: getStepStatus(index) === 'completed' ? '#000' : 
                                        getStepStatus(index) === 'active' ? '#f3f4f6' : '#fff'
                       }}>
                    {getStepIcon(index, step.icon)}
                  </div>
                  <div className="text-center">
                    <div className={`text-xs font-semibold mb-1 uppercase tracking-wide ${
                      getStepStatus(index) === 'completed' ? 'text-black' :
                      getStepStatus(index) === 'active' ? 'text-black' : 'text-gray-400'
                    }`}>
                      {step.label}
                    </div>
                    {getStepStatus(index) === 'active' && (
                      <div className="text-xs text-gray-500 mt-1">{step.description}</div>
                    )}
                  </div>
                  {index < steps.length - 1 && (
                    <div className={`absolute top-7 left-1/2 h-0.5 -z-10 ${
                      getStepStatus(index) === 'completed' ? 'bg-black' : 'bg-gray-200'
                    }`} style={{ width: 'calc(100% - 3.5rem)', marginLeft: '1.75rem' }} />
                  )}
                </div>
              ))}
            </div>

            {/* Progress Bar */}
            <div className="w-full bg-gray-100 rounded-full h-2 mb-6">
              <div 
                className="bg-black h-2 rounded-full transition-all duration-500"
                style={{ width: `${scanStatus?.progress || 0}%` }}
              ></div>
            </div>

            {/* Status Message */}
            <div className="text-center">
              <div className="text-lg font-semibold text-gray-900 mb-3">
                {scanStatus?.message || 'Initializing analysis...'}
              </div>
              <div className="flex items-center justify-center space-x-6 text-sm text-gray-600 mb-6">
                <div className="flex items-center">
                  <Clock className="h-4 w-4 mr-2 text-blue-600" />
                  <span className="font-medium">{elapsedTime}s elapsed</span>
                </div>
                <div className="w-px h-4 bg-gray-300"></div>
                <div className="flex items-center">
                  <Clock className="h-4 w-4 mr-2 text-orange-600" />
                  <span>{timeRemaining}s remaining</span>
                </div>
                <div className="w-px h-4 bg-gray-300"></div>
                <div className="flex items-center">
                  <Activity className="h-4 w-4 mr-2 text-green-600" />
                  <span>{scanStatus?.progress || 0}% complete</span>
                </div>
              </div>

              {/* Fun Fact */}
              <div className="bg-gradient-to-r from-blue-50 to-purple-50 rounded-lg p-4 border border-blue-200 max-w-2xl mx-auto">
                <div className="flex items-start gap-3">
                  {(() => {
                    const CurrentIcon = funFacts[currentFactIndex].icon
                    return <CurrentIcon className="h-5 w-5 text-blue-600 mt-0.5 flex-shrink-0" />
                  })()}
                  <div className="text-left">
                    <div className="flex items-center gap-2 mb-1">
                      <Lightbulb className="h-4 w-4 text-yellow-600" />
                      <span className="text-xs font-semibold text-gray-700 uppercase tracking-wide">
                        Did you know?
                      </span>
                    </div>
                    <p className="text-sm text-gray-700 leading-relaxed mb-1">
                      {funFacts[currentFactIndex].text}
                    </p>
                    <p className="text-xs text-gray-500 italic">
                      — {funFacts[currentFactIndex].source}
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Current Analysis Details */}
        {scanStatus && (
          <Card className="border-gray-200">
            <CardContent className="p-8">
              <div className="text-center">
                {/* Sub-task indicator */}
                <div className="mb-8">
                  <div className="inline-flex items-center gap-2 px-4 py-2 bg-black text-white rounded-full text-sm font-medium">
                    <Loader2 className="h-4 w-4 animate-spin" />
                    <span>{getSubTask()}</span>
                  </div>
                </div>

                {scanStatus.status === 'completed' && (
                  <div className="text-center">
                    <CheckCircle className="h-16 w-16 text-black mx-auto mb-4" />
                    <h3 className="text-2xl font-bold text-gray-900 mb-2">
                      Analysis Complete!
                    </h3>
                    <p className="text-gray-600 mb-6">
                      Your comprehensive WordPress audit report is ready.
                    </p>
                    <Button 
                      onClick={() => window.location.href = `/report/${scanStatus.result?.id}`}
                      size="lg"
                      className="bg-black hover:bg-gray-800 text-white"
                    >
                      View Report
                    </Button>
                  </div>
                )}

                {scanStatus.status === 'failed' && (
                  <div className="text-center">
                    <div className="h-16 w-16 bg-red-50 rounded-lg flex items-center justify-center mx-auto mb-4">
                      <AlertTriangle className="h-8 w-8 text-red-600" />
                    </div>
                    <h3 className="text-2xl font-bold text-gray-900 mb-2">
                      Analysis Failed
                    </h3>
                    <p className="text-gray-600 mb-6">
                      There was an error analyzing your website. Please try again.
                    </p>
                    <Button 
                      onClick={() => window.location.href = '/'}
                      variant="outline"
                      className="border-gray-200"
                    >
                      Try Again
                    </Button>
                  </div>
                )}
              </div>
            </CardContent>
          </Card>
        )}

        {/* Footer */}
        <div className="text-center mt-8 text-gray-500 text-sm">
          <p>Powered by Google Lighthouse</p>
        </div>
      </div>
    </div>
  )
}
