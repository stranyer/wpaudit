import Link from 'next/link'
import { Button } from '@/components/ui/button'
import { Zap, ArrowLeft } from 'lucide-react'

interface AppHeaderProps {
  variant?: 'landing' | 'app'
  showBackButton?: boolean
  transparent?: boolean
}

export function AppHeader({ 
  variant = 'landing', 
  showBackButton = false,
  transparent = false 
}: AppHeaderProps) {
  const isLanding = variant === 'landing'
  
  return (
    <header className={`fixed top-0 left-0 right-0 z-50 border-b border-gray-100 ${
      transparent 
        ? 'bg-white/80 backdrop-blur-md' 
        : 'bg-white'
    }`}>
      <nav className="container mx-auto px-4 lg:px-8">
        <div className="flex items-center justify-between h-16">
          {/* Left side */}
          <div className="flex items-center gap-4">
            {showBackButton && (
              <Link 
                href="/"
                className="flex items-center gap-2 text-sm font-medium text-gray-600 hover:text-gray-900 transition-colors"
              >
                <ArrowLeft className="h-4 w-4" />
                <span className="hidden sm:inline">Back to Home</span>
              </Link>
            )}
            
            {!showBackButton && (
              <Link href="/" className="flex items-center gap-2">
                <div className="w-8 h-8 bg-gradient-to-br from-emerald-500 to-teal-600 rounded-lg flex items-center justify-center">
                  <Zap className="h-5 w-5 text-white" />
                </div>
                <span className="text-xl font-bold text-gray-900">Just Speed It</span>
              </Link>
            )}
          </div>

          {/* Right side */}
          {isLanding && (
            <div className="flex items-center gap-6">
              <Link 
                href="/documentation" 
                className="text-sm font-medium text-gray-600 hover:text-gray-900 transition-colors"
              >
                Docs
              </Link>
              <Button 
                variant="outline" 
                size="sm"
                onClick={() => document.getElementById('audit-form')?.scrollIntoView({ behavior: 'smooth' })}
                className="border-gray-200"
              >
                Get Started
              </Button>
            </div>
          )}
        </div>
      </nav>
    </header>
  )
}

