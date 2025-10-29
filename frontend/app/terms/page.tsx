export default function TermsOfService() {
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
            <a href="/" className="text-gray-600 hover:text-gray-900 transition-colors text-sm font-medium">
              ← Back to Home
            </a>
          </div>
        </div>
      </header>

      {/* Content */}
      <div className="container mx-auto px-4 py-16 max-w-4xl">
        <h1 className="text-4xl font-bold text-gray-900 mb-8">Terms of Service</h1>
        
        <div className="prose prose-lg max-w-none">
          <p className="text-gray-600 mb-8">
            <strong>Last Updated:</strong> {new Date().toLocaleDateString()}
          </p>

          <section className="mb-8">
            <h2 className="text-2xl font-bold text-gray-900 mb-4">1. Acceptance of Terms</h2>
            <p className="text-gray-700 leading-relaxed mb-4">
              By accessing and using Just Speed It ("the Service"), you accept and agree to be bound by the terms 
              and provision of this agreement. If you do not agree to these Terms of Service, please do not use the Service.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-bold text-gray-900 mb-4">2. Description of Service</h2>
            <p className="text-gray-700 leading-relaxed mb-4">
              Just Speed It provides a free WordPress performance audit service powered by Google Lighthouse. 
              The Service analyzes publicly accessible websites and provides reports on:
            </p>
            <ul className="list-disc pl-6 text-gray-700 space-y-2">
              <li>Performance metrics (Core Web Vitals, loading times)</li>
              <li>SEO analysis</li>
              <li>Security checks</li>
              <li>Accessibility evaluation</li>
              <li>Best practices recommendations</li>
            </ul>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-bold text-gray-900 mb-4">3. User Responsibilities</h2>
            <p className="text-gray-700 leading-relaxed mb-4">
              You agree to:
            </p>
            <ul className="list-disc pl-6 text-gray-700 space-y-2">
              <li>Only submit URLs of websites you own or have permission to audit</li>
              <li>Not use the Service for malicious purposes</li>
              <li>Not attempt to overload or hack the Service</li>
              <li>Comply with all applicable laws and regulations</li>
            </ul>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-bold text-gray-900 mb-4">4. Service Availability</h2>
            <p className="text-gray-700 leading-relaxed">
              We strive to provide uninterrupted access to the Service, but we do not guarantee that the Service 
              will be available at all times. We reserve the right to modify, suspend, or discontinue the Service 
              (or any part thereof) at any time without notice.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-bold text-gray-900 mb-4">5. Intellectual Property</h2>
            <p className="text-gray-700 leading-relaxed mb-4">
              The Service and its original content, features, and functionality are owned by Just Speed It and are 
              protected by international copyright, trademark, patent, trade secret, and other intellectual property laws.
            </p>
            <p className="text-gray-700 leading-relaxed">
              Audit reports generated for your websites are yours to use and share as you see fit.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-bold text-gray-900 mb-4">6. Disclaimer of Warranties</h2>
            <p className="text-gray-700 leading-relaxed mb-4">
              THE SERVICE IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR IMPLIED, 
              INCLUDING BUT NOT LIMITED TO:
            </p>
            <ul className="list-disc pl-6 text-gray-700 space-y-2">
              <li>Accuracy or completeness of audit results</li>
              <li>Fitness for a particular purpose</li>
              <li>Non-infringement</li>
              <li>Uninterrupted or error-free service</li>
            </ul>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-bold text-gray-900 mb-4">7. Limitation of Liability</h2>
            <p className="text-gray-700 leading-relaxed">
              In no event shall Just Speed It be liable for any indirect, incidental, special, consequential, or punitive 
              damages, including without limitation, loss of profits, data, use, goodwill, or other intangible losses, 
              resulting from your use of the Service.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-bold text-gray-900 mb-4">8. Rate Limiting</h2>
            <p className="text-gray-700 leading-relaxed">
              To ensure fair usage and service availability for all users, we implement rate limiting. Excessive use 
              may result in temporary suspension of access to the Service.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-bold text-gray-900 mb-4">9. Data and Privacy</h2>
            <p className="text-gray-700 leading-relaxed">
              Your use of the Service is also governed by our{' '}
              <a href="/privacy" className="text-blue-600 hover:underline">Privacy Policy</a>. 
              Please review it to understand our practices.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-bold text-gray-900 mb-4">10. Changes to Terms</h2>
            <p className="text-gray-700 leading-relaxed">
              We reserve the right to modify or replace these Terms at any time. If a revision is material, 
              we will provide at least 30 days notice prior to any new terms taking effect.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-bold text-gray-900 mb-4">11. Governing Law</h2>
            <p className="text-gray-700 leading-relaxed">
              These Terms shall be governed by and construed in accordance with applicable international laws, 
              without regard to conflict of law provisions.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-bold text-gray-900 mb-4">12. Contact Information</h2>
            <p className="text-gray-700 leading-relaxed">
              If you have any questions about these Terms, please contact us at:
            </p>
            <p className="text-gray-700 mt-4">
              <strong>Email:</strong> <a href="mailto:info@justspeedit.com" className="text-blue-600 hover:underline">info@justspeedit.com</a>
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-bold text-gray-900 mb-4">13. Severability</h2>
            <p className="text-gray-700 leading-relaxed">
              If any provision of these Terms is held to be invalid or unenforceable, such provision shall be struck 
              and the remaining provisions shall be enforced.
            </p>
          </section>
        </div>
      </div>

      {/* Footer */}
      <footer className="border-t border-gray-200 bg-gradient-to-b from-gray-50 to-white mt-16">
        <div className="container mx-auto px-4 py-12">
          <div className="flex flex-col md:flex-row justify-between items-center">
            <div className="flex items-center space-x-2 mb-6 md:mb-0">
              <div className="h-8 w-8 bg-gradient-to-br from-green-400 via-blue-500 to-purple-600 rounded-lg flex items-center justify-center shadow-md">
                <span className="text-white font-bold">⚡</span>
              </div>
              <span className="font-bold bg-gradient-to-r from-gray-900 to-gray-600 bg-clip-text text-transparent">
                Just Speed It
              </span>
            </div>
            
            <div className="flex items-center space-x-8 text-sm text-gray-600">
              <a href="/documentation" className="hover:text-gray-900 transition-colors font-medium">Documentation</a>
              <a href="/privacy" className="hover:text-gray-900 transition-colors font-medium">Privacy</a>
              <a href="/terms" className="hover:text-gray-900 transition-colors font-medium">Terms</a>
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

