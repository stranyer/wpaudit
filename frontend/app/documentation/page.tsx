import { CheckCircle, Code, Gauge, Lock, TrendingUp, Zap, Camera, FileSearch } from 'lucide-react'

export default function Documentation() {
  return (
    <div className="min-h-screen bg-gradient-to-b from-white via-gray-50 to-white">
      {/* Header */}
      <header className="border-b border-gray-200 bg-white/80 backdrop-blur-sm">
        <div className="container mx-auto px-4 py-4">
          <div className="flex items-center justify-between">
            <a href="/" className="flex items-center space-x-2">
              <div className="h-9 w-9 bg-gradient-to-br from-green-400 via-blue-500 to-purple-600 rounded-xl flex items-center justify-center shadow-lg">
                <span className="text-white font-bold text-xl">⚡</span>
              </div>
              <span className="text-xl font-bold bg-gradient-to-r from-gray-900 to-gray-600 bg-clip-text text-transparent">
                Just Speed It
              </span>
            </a>
            <a href="/" className="text-gray-600 hover:text-gray-900 transition-colors text-sm font-medium">← Back to Home</a>
          </div>
        </div>
      </header>

      {/* Content */}
      <div className="container mx-auto px-4 py-16">
        <div className="max-w-4xl mx-auto">
          <h1 className="text-4xl font-bold text-gray-900 mb-4">Documentation</h1>
          <p className="text-xl text-gray-600 mb-12">
            Learn how to use Just Speed It to improve your WordPress performance, SEO, and security.
          </p>

          {/* Quick Start */}
          <section className="mb-12 p-8 bg-gradient-to-br from-green-50 to-blue-50 rounded-2xl border border-green-100">
            <h2 className="text-2xl font-bold text-gray-900 mb-4">Quick Start</h2>
            <ol className="space-y-4">
              <li className="flex gap-4">
                <div className="flex-shrink-0 w-8 h-8 bg-black text-white rounded-full flex items-center justify-center font-bold">
                  1
                </div>
                <div>
                  <p className="font-medium text-gray-900">Enter your WordPress URL</p>
                  <p className="text-gray-600">Simply paste your website URL in the input field on the homepage.</p>
                </div>
              </li>
              <li className="flex gap-4">
                <div className="flex-shrink-0 w-8 h-8 bg-black text-white rounded-full flex items-center justify-center font-bold">
                  2
                </div>
                <div>
                  <p className="font-medium text-gray-900">Wait 60-90 seconds</p>
                  <p className="text-gray-600">Our system will analyze your site using Google Lighthouse.</p>
                </div>
              </li>
              <li className="flex gap-4">
                <div className="flex-shrink-0 w-8 h-8 bg-black text-white rounded-full flex items-center justify-center font-bold">
                  3
                </div>
                <div>
                  <p className="font-medium text-gray-900">Review your comprehensive report</p>
                  <p className="text-gray-600">Get actionable insights with prioritized recommendations.</p>
                </div>
              </li>
            </ol>
          </section>

          {/* What We Analyze */}
          <section className="mb-12">
            <h2 className="text-3xl font-bold text-gray-900 mb-8">What We Analyze</h2>
            
            <div className="grid md:grid-cols-2 gap-6">
              <div className="p-6 border-2 border-gray-200 rounded-xl hover:border-green-400 transition-colors">
                <div className="flex items-center gap-3 mb-4">
                  <div className="p-3 bg-gray-100 rounded-lg">
                    <Gauge className="h-6 w-6" />
                  </div>
                  <h3 className="text-xl font-bold text-gray-900">Performance</h3>
                </div>
                <ul className="space-y-2 text-gray-700">
                  <li className="flex items-start gap-2">
                    <CheckCircle className="h-5 w-5 text-green-500 flex-shrink-0 mt-0.5" />
                    <span>Core Web Vitals (LCP, CLS, INP)</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <CheckCircle className="h-5 w-5 text-green-500 flex-shrink-0 mt-0.5" />
                    <span>Loading times (TTFB, FCP, TTI)</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <CheckCircle className="h-5 w-5 text-green-500 flex-shrink-0 mt-0.5" />
                    <span>Resource optimization opportunities</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <CheckCircle className="h-5 w-5 text-green-500 flex-shrink-0 mt-0.5" />
                    <span>Mobile & Desktop performance scores</span>
                  </li>
                </ul>
              </div>

              <div className="p-6 border-2 border-gray-200 rounded-xl hover:border-blue-400 transition-colors">
                <div className="flex items-center gap-3 mb-4">
                  <div className="p-3 bg-gray-100 rounded-lg">
                    <TrendingUp className="h-6 w-6" />
                  </div>
                  <h3 className="text-xl font-bold text-gray-900">SEO</h3>
                </div>
                <ul className="space-y-2 text-gray-700">
                  <li className="flex items-start gap-2">
                    <CheckCircle className="h-5 w-5 text-blue-500 flex-shrink-0 mt-0.5" />
                    <span>Meta tags (title, description)</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <CheckCircle className="h-5 w-5 text-blue-500 flex-shrink-0 mt-0.5" />
                    <span>Open Graph & Twitter Cards</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <CheckCircle className="h-5 w-5 text-blue-500 flex-shrink-0 mt-0.5" />
                    <span>Heading structure (H1, H2, etc.)</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <CheckCircle className="h-5 w-5 text-blue-500 flex-shrink-0 mt-0.5" />
                    <span>Image alt texts & accessibility</span>
                  </li>
                </ul>
              </div>

              <div className="p-6 border-2 border-gray-200 rounded-xl hover:border-purple-400 transition-colors">
                <div className="flex items-center gap-3 mb-4">
                  <div className="p-3 bg-gray-100 rounded-lg">
                    <Lock className="h-6 w-6" />
                  </div>
                  <h3 className="text-xl font-bold text-gray-900">Security</h3>
                </div>
                <ul className="space-y-2 text-gray-700">
                  <li className="flex items-start gap-2">
                    <CheckCircle className="h-5 w-5 text-purple-500 flex-shrink-0 mt-0.5" />
                    <span>Security headers (CSP, HSTS, etc.)</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <CheckCircle className="h-5 w-5 text-purple-500 flex-shrink-0 mt-0.5" />
                    <span>WordPress version detection</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <CheckCircle className="h-5 w-5 text-purple-500 flex-shrink-0 mt-0.5" />
                    <span>Exposed sensitive files</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <CheckCircle className="h-5 w-5 text-purple-500 flex-shrink-0 mt-0.5" />
                    <span>SSL/HTTPS configuration</span>
                  </li>
                </ul>
              </div>

              <div className="p-6 border-2 border-gray-200 rounded-xl hover:border-orange-400 transition-colors">
                <div className="flex items-center gap-3 mb-4">
                  <div className="p-3 bg-gray-100 rounded-lg">
                    <Code className="h-6 w-6" />
                  </div>
                  <h3 className="text-xl font-bold text-gray-900">WordPress Specific</h3>
                </div>
                <ul className="space-y-2 text-gray-700">
                  <li className="flex items-start gap-2">
                    <CheckCircle className="h-5 w-5 text-orange-500 flex-shrink-0 mt-0.5" />
                    <span>Theme detection & analysis</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <CheckCircle className="h-5 w-5 text-orange-500 flex-shrink-0 mt-0.5" />
                    <span>Plugin identification</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <CheckCircle className="h-5 w-5 text-orange-500 flex-shrink-0 mt-0.5" />
                    <span>Heavy plugins impact analysis</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <CheckCircle className="h-5 w-5 text-orange-500 flex-shrink-0 mt-0.5" />
                    <span>Outdated plugins & security risks</span>
                  </li>
                </ul>
              </div>
            </div>
          </section>

          {/* Understanding Your Report */}
          <section className="mb-12">
            <h2 className="text-3xl font-bold text-gray-900 mb-6">Understanding Your Report</h2>
            
            <div className="space-y-6">
              <div className="p-6 bg-gray-50 rounded-xl">
                <h3 className="text-xl font-bold text-gray-900 mb-3">Performance Scores</h3>
                <p className="text-gray-700 mb-4">
                  Scores range from 0-100. Higher is better:
                </p>
                <div className="grid md:grid-cols-3 gap-4">
                  <div className="p-4 bg-red-50 border-2 border-red-200 rounded-lg">
                    <p className="font-bold text-red-700">0-49: Poor</p>
                    <p className="text-sm text-red-600">Needs immediate attention</p>
                  </div>
                  <div className="p-4 bg-yellow-50 border-2 border-yellow-200 rounded-lg">
                    <p className="font-bold text-yellow-700">50-89: Needs Improvement</p>
                    <p className="text-sm text-yellow-600">Room for optimization</p>
                  </div>
                  <div className="p-4 bg-green-50 border-2 border-green-200 rounded-lg">
                    <p className="font-bold text-green-700">90-100: Good</p>
                    <p className="text-sm text-green-600">Well optimized</p>
                  </div>
                </div>
              </div>

              <div className="p-6 bg-gray-50 rounded-xl">
                <h3 className="text-xl font-bold text-gray-900 mb-3">Core Web Vitals</h3>
                <div className="space-y-4">
                  <div>
                    <p className="font-semibold text-gray-900">LCP (Largest Contentful Paint)</p>
                    <p className="text-gray-700">Time until the largest content element is visible. Target: &lt; 2.5s</p>
                  </div>
                  <div>
                    <p className="font-semibold text-gray-900">CLS (Cumulative Layout Shift)</p>
                    <p className="text-gray-700">Visual stability measure. Target: &lt; 0.1</p>
                  </div>
                  <div>
                    <p className="font-semibold text-gray-900">INP (Interaction to Next Paint)</p>
                    <p className="text-gray-700">Responsiveness to user interactions. Target: &lt; 200ms</p>
                  </div>
                </div>
              </div>

              <div className="p-6 bg-gray-50 rounded-xl">
                <h3 className="text-xl font-bold text-gray-900 mb-3">Priority Recommendations</h3>
                <p className="text-gray-700 mb-4">
                  Each recommendation includes:
                </p>
                <ul className="space-y-2 text-gray-700">
                  <li className="flex items-start gap-2">
                    <div className="w-2 h-2 bg-red-500 rounded-full mt-2 flex-shrink-0"></div>
                    <span><strong>Impact:</strong> High, Medium, or Low - how much it affects your site</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <div className="w-2 h-2 bg-blue-500 rounded-full mt-2 flex-shrink-0"></div>
                    <span><strong>Effort:</strong> XS, S, M, L - estimated time to implement</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <div className="w-2 h-2 bg-green-500 rounded-full mt-2 flex-shrink-0"></div>
                    <span><strong>Expected Savings:</strong> Performance improvement you can expect</span>
                  </li>
                </ul>
              </div>
            </div>
          </section>

          {/* FAQ */}
          <section className="mb-12">
            <h2 className="text-3xl font-bold text-gray-900 mb-6">Frequently Asked Questions</h2>
            
            <div className="space-y-4">
              <details className="p-6 bg-gray-50 rounded-xl cursor-pointer">
                <summary className="font-bold text-gray-900 cursor-pointer">Is Just Speed It really free?</summary>
                <p className="mt-3 text-gray-700">
                  Yes! Just Speed It is 100% free with no hidden costs, no credit card required, and no signup needed.
                </p>
              </details>

              <details className="p-6 bg-gray-50 rounded-xl cursor-pointer">
                <summary className="font-bold text-gray-900 cursor-pointer">How accurate are the results?</summary>
                <p className="mt-3 text-gray-700">
                  We use Google Lighthouse, the same tool used by Google PageSpeed Insights. Results are highly accurate 
                  and reflect real-world performance metrics.
                </p>
              </details>

              <details className="p-6 bg-gray-50 rounded-xl cursor-pointer">
                <summary className="font-bold text-gray-900 cursor-pointer">Can I scan any website?</summary>
                <p className="mt-3 text-gray-700">
                  You can scan any publicly accessible website. However, we're optimized for WordPress sites and provide 
                  WordPress-specific insights.
                </p>
              </details>

              <details className="p-6 bg-gray-50 rounded-xl cursor-pointer">
                <summary className="font-bold text-gray-900 cursor-pointer">How often should I audit my site?</summary>
                <p className="mt-3 text-gray-700">
                  We recommend auditing after major changes (theme updates, new plugins, content changes) or at least 
                  monthly to track improvements.
                </p>
              </details>

              <details className="p-6 bg-gray-50 rounded-xl cursor-pointer">
                <summary className="font-bold text-gray-900 cursor-pointer">Can I share my report?</summary>
                <p className="mt-3 text-gray-700">
                  Yes! Each report has a unique URL you can share with clients, developers, or team members. 
                  You can also export as PDF.
                </p>
              </details>
            </div>
          </section>

          {/* CTA */}
          <section className="p-8 bg-gradient-to-br from-green-500 to-blue-500 rounded-2xl text-white text-center">
            <h2 className="text-3xl font-bold mb-4">Ready to Optimize Your WordPress Site?</h2>
            <p className="text-lg mb-6 text-green-50">
              Get your free comprehensive audit in 60 seconds
            </p>
            <a 
              href="/" 
              className="inline-block px-8 py-4 bg-white text-gray-900 font-bold rounded-lg hover:bg-gray-100 transition-colors"
            >
              Start Free Audit →
            </a>
          </section>
        </div>
      </div>

      {/* Footer */}
      <footer className="border-t border-gray-200 bg-gradient-to-b from-gray-50 to-white mt-16">
        <div className="container mx-auto px-4 py-12">
          <div className="flex flex-col md:flex-row justify-between items-center gap-4">
            <div className="flex items-center space-x-2">
              <div className="h-8 w-8 bg-gradient-to-br from-green-400 via-blue-500 to-purple-600 rounded-lg flex items-center justify-center shadow-md">
                <span className="text-white font-bold">⚡</span>
              </div>
              <span className="font-bold bg-gradient-to-r from-gray-900 to-gray-600 bg-clip-text text-transparent">
                Just Speed It
              </span>
            </div>
            <div className="flex gap-6">
              <a href="/privacy" className="text-gray-600 hover:text-gray-900 text-sm font-medium transition-colors">Privacy</a>
              <a href="/terms" className="text-gray-600 hover:text-gray-900 text-sm font-medium transition-colors">Terms</a>
            </div>
          </div>
          
          <div className="mt-8 pt-8 border-t border-gray-200 text-center text-sm text-gray-500">
            <p>&copy; {new Date().getFullYear()} Just Speed It. All rights reserved.</p>
          </div>
        </div>
      </footer>
    </div>
  )
}

