'use client'

import { useState, useEffect } from 'react'
import { useParams, useRouter } from 'next/navigation'
import { AppHeader } from '@/components/layout/AppHeader'
import { AppFooter } from '@/components/layout/AppFooter'
import { 
  Globe, 
  Activity, 
  Shield,
  Search,
  CheckCircle2,
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

const SCAN_STEPS = [
  { 
    id: 'performance', 
    label: 'Performance Analysis', 
    icon: Activity,
    description: 'Testing mobile & desktop speed'
  },
  { 
    id: 'security', 
    label: 'Security Scan', 
    icon: Shield,
    description: 'Checking vulnerabilities'
  },
  { 
    id: 'seo', 
    label: 'SEO Audit', 
    icon: Search,
    description: 'Analyzing meta tags & structure'
  },
  { 
    id: 'wordpress', 
    label: 'WordPress Analysis', 
    icon: Globe,
    description: 'Detecting plugins & theme'
  }
]

export default function ScanningPage() {
  const params = useParams()
  const router = useRouter()
  const [scanStatus, setScanStatus] = useState<ScanStatus | null>(null)
  const [currentStepIndex, setCurrentStepIndex] = useState(0)
  const [elapsedTime, setElapsedTime] = useState(0)

  useEffect(() => {
    if (!params.jobId) return

    const pollStatus = async () => {
      try {
        const response = await fetch(`/api/scan/${params.jobId}`)
        const data = await response.json()
        
        console.log('Scan status:', data)
        setScanStatus(data)

        // Update current step based on progress
        const stepIndex = Math.min(
          Math.floor((data.progress / 100) * SCAN_STEPS.length),
          SCAN_STEPS.length - 1
        )
        setCurrentStepIndex(stepIndex)

        // Redirect when completed
        if (data.status === 'completed') {
          console.log('Scan completed! Result:', data.result)
          console.log('PublicId:', data.result?.publicId)
          
          // Try different possible response structures
          const reportId = data.result?.publicId || data.result?.id || data.reportId
          
          if (reportId) {
            console.log('Redirecting to report:', reportId)
            setTimeout(() => {
              router.push(`/report/${reportId}`)
            }, 1000)
          } else {
            console.error('No report ID found in response:', data)
          }
        }
      } catch (error) {
        console.error('Error polling scan status:', error)
      }
    }

    // Initial poll
    pollStatus()
    
    // Poll every 2 seconds
    const pollInterval = setInterval(pollStatus, 2000)
    
    // Elapsed time counter
    const timeInterval = setInterval(() => {
      setElapsedTime(prev => prev + 1)
    }, 1000)

    return () => {
      clearInterval(pollInterval)
      clearInterval(timeInterval)
    }
  }, [params.jobId, router])

  const progress = scanStatus?.progress || 0
  const isComplete = scanStatus?.status === 'completed'

  return (
    <div className="min-h-screen flex flex-col bg-gradient-to-b from-emerald-50/30 to-white">
      <AppHeader variant="app" showBackButton={false} />
      
      <main className="flex-1 flex items-center justify-center px-4 py-20">
        <div className="w-full max-w-2xl">
          
          {/* Main Card */}
          <div className="bg-white rounded-2xl border border-gray-200 shadow-xl p-8 md:p-12">
            
            {/* Animated Icon */}
            <div className="flex justify-center mb-8">
              <div className="relative">
                <div className="w-20 h-20 bg-gradient-to-br from-emerald-500 to-teal-600 rounded-2xl flex items-center justify-center animate-pulse">
                  <Globe className="h-10 w-10 text-white" />
                </div>
                {/* Rotating border */}
                <div className="absolute inset-0 rounded-2xl border-4 border-emerald-200 animate-spin" 
                     style={{ animationDuration: '3s' }}></div>
              </div>
            </div>

            {/* Status Text */}
            <div className="text-center mb-8">
              <h1 className="text-2xl md:text-3xl font-bold text-gray-900 mb-2">
                {isComplete ? 'Analysis Complete!' : 'Analyzing Your Website'}
              </h1>
              <p className="text-gray-600">
                {scanStatus?.message || 'Initializing scan...'}
              </p>
            </div>

            {/* Progress Bar */}
            <div className="mb-8">
              <div className="flex items-center justify-between text-sm text-gray-600 mb-2">
                <span>Progress</span>
                <span className="font-semibold">{Math.round(progress)}%</span>
              </div>
              <div className="h-3 bg-gray-100 rounded-full overflow-hidden">
                <div 
                  className="h-full bg-gradient-to-r from-emerald-500 to-teal-600 rounded-full transition-all duration-500 ease-out"
                  style={{ width: `${progress}%` }}
                />
              </div>
            </div>

            {/* Steps List */}
            <div className="space-y-3 mb-8">
              {SCAN_STEPS.map((step, index) => {
                const isActive = index === currentStepIndex && !isComplete
                const isDone = index < currentStepIndex || isComplete
                const Icon = step.icon

                return (
                  <div 
                    key={step.id}
                    className={`flex items-center gap-3 p-3 rounded-lg transition-all ${
                      isActive ? 'bg-emerald-50 border border-emerald-200' : 
                      isDone ? 'bg-gray-50' : 
                      'bg-white'
                    }`}
                  >
                    <div className={`flex-shrink-0 w-10 h-10 rounded-lg flex items-center justify-center ${
                      isDone ? 'bg-emerald-100' :
                      isActive ? 'bg-emerald-500' :
                      'bg-gray-100'
                    }`}>
                      {isDone ? (
                        <CheckCircle2 className="h-5 w-5 text-emerald-600" />
                      ) : isActive ? (
                        <Loader2 className="h-5 w-5 text-white animate-spin" />
                      ) : (
                        <Icon className="h-5 w-5 text-gray-400" />
                      )}
                    </div>
                    
                    <div className="flex-1 min-w-0">
                      <div className={`font-semibold text-sm ${
                        isActive ? 'text-emerald-900' :
                        isDone ? 'text-gray-700' :
                        'text-gray-400'
                      }`}>
                        {step.label}
                      </div>
                      <div className={`text-xs ${
                        isActive ? 'text-emerald-700' :
                        isDone ? 'text-gray-500' :
                        'text-gray-400'
                      }`}>
                        {step.description}
                      </div>
                    </div>
                  </div>
                )
              })}
            </div>

            {/* Time Estimate */}
            <div className="text-center text-sm text-gray-500">
              <div className="inline-flex items-center gap-2 px-4 py-2 bg-gray-50 rounded-full">
                <Activity className="h-4 w-4" />
                <span>Elapsed: {elapsedTime}s • Estimated: ~60s</span>
              </div>
            </div>

          </div>

          {/* Info Note */}
          <div className="mt-6 text-center">
            <p className="text-sm text-gray-500">
              We're analyzing your site with Google Lighthouse and our WordPress-specific checks.
              <br />
              This usually takes 30-60 seconds.
            </p>
          </div>

        </div>
      </main>

      <AppFooter />
    </div>
  )
}
