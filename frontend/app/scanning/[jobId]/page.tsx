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
  Loader2
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

export default function ScanningPage() {
  const params = useParams()
  const [scanStatus, setScanStatus] = useState<ScanStatus | null>(null)
  const [currentStep, setCurrentStep] = useState(0)
  const [timeRemaining, setTimeRemaining] = useState(60)

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

    // Countdown timer
    const timer = setInterval(() => {
      setTimeRemaining(prev => {
        if (prev <= 1) {
          clearInterval(timer)
          return 0
        }
        return prev - 1
      })
    }, 1000)

    return () => clearInterval(timer)
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
              <div className="flex items-center justify-center space-x-6 text-sm text-gray-600">
                <div className="flex items-center">
                  <Clock className="h-4 w-4 mr-2" />
                  <span>{timeRemaining}s remaining</span>
                </div>
                <div className="flex items-center">
                  <Activity className="h-4 w-4 mr-2" />
                  <span>{scanStatus?.progress || 0}% complete</span>
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
                <h3 className="text-xl font-semibold text-gray-900 mb-6">
                  {steps[currentStep]?.description || 'Processing your website...'}
                </h3>
                
                <div className="grid md:grid-cols-3 gap-4 mb-8">
                  <div className="text-center p-6 bg-gray-50 rounded-lg border border-gray-100">
                    <div className="text-3xl font-bold text-gray-900 mb-1">
                      {scanStatus.progress}%
                    </div>
                    <div className="text-sm text-gray-600">Complete</div>
                  </div>
                  <div className="text-center p-6 bg-gray-50 rounded-lg border border-gray-100">
                    <div className="text-3xl font-bold text-gray-900 mb-1">
                      {timeRemaining}s
                    </div>
                    <div className="text-sm text-gray-600">Remaining</div>
                  </div>
                  <div className="text-center p-6 bg-gray-50 rounded-lg border border-gray-100">
                    <div className="text-3xl font-bold text-gray-900 mb-1">
                      <Zap className="h-8 w-8 mx-auto" />
                    </div>
                    <div className="text-sm text-gray-600">Lighthouse</div>
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
