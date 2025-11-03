(function() {
  'use strict';

  // Configuration
  const API_BASE_URL = window.JUSTSPEEDIT_API_URL || 'https://wpaudit-production.up.railway.app';
  
  // Widget Class
  class JustSpeedItWidget {
    constructor(containerId) {
      this.container = document.getElementById(containerId);
      if (!this.container) {
        console.error('JustSpeedIt: Container not found');
        return;
      }
      this.init();
    }

    init() {
      this.injectStyles();
      this.render();
      this.attachEventListeners();
    }

    injectStyles() {
      const styles = `
        .jsi-widget {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
          max-width: 800px;
          margin: 0 auto;
          padding: 20px;
        }
        
        .jsi-hero {
          text-align: center;
          padding: 40px 20px;
        }
        
        .jsi-title {
          font-size: 2.5rem;
          font-weight: 800;
          line-height: 1.2;
          margin: 0 0 20px 0;
          color: #111827;
        }
        
        .jsi-subtitle {
          font-size: 1.125rem;
          line-height: 1.75;
          color: #4B5563;
          margin: 0 0 30px 0;
          max-width: 600px;
          margin-left: auto;
          margin-right: auto;
        }
        
        .jsi-form {
          display: flex;
          flex-direction: column;
          gap: 12px;
          max-width: 550px;
          margin: 0 auto;
          background: white;
          padding: 8px;
          border-radius: 16px;
          box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1);
        }
        
        @media (min-width: 640px) {
          .jsi-form {
            flex-direction: row;
            gap: 0;
          }
        }
        
        .jsi-input {
          flex: 1;
          padding: 12px 16px;
          font-size: 16px;
          border: none;
          border-radius: 12px;
          outline: none;
          color: #111827;
        }
        
        .jsi-input:focus {
          outline: 2px solid #10B981;
          outline-offset: 2px;
        }
        
        .jsi-button {
          padding: 12px 24px;
          font-size: 16px;
          font-weight: 600;
          color: white;
          background: #111827;
          border: none;
          border-radius: 12px;
          cursor: pointer;
          transition: all 0.2s;
          min-width: 150px;
        }
        
        .jsi-button:hover:not(:disabled) {
          background: #1F2937;
          transform: translateY(-1px);
        }
        
        .jsi-button:disabled {
          opacity: 0.6;
          cursor: not-allowed;
        }
        
        .jsi-badges {
          display: flex;
          flex-wrap: wrap;
          justify-content: center;
          gap: 16px;
          margin-top: 24px;
          font-size: 14px;
          color: #6B7280;
        }
        
        .jsi-badge {
          display: flex;
          align-items: center;
          gap: 6px;
        }
        
        .jsi-badge svg {
          width: 16px;
          height: 16px;
          color: #10B981;
        }
        
        .jsi-error {
          margin-top: 16px;
          padding: 12px 16px;
          background: #FEE2E2;
          color: #991B1B;
          border-radius: 8px;
          font-size: 14px;
          text-align: center;
        }
        
        .jsi-spinner {
          display: inline-block;
          width: 16px;
          height: 16px;
          border: 2px solid #ffffff;
          border-top-color: transparent;
          border-radius: 50%;
          animation: jsi-spin 0.6s linear infinite;
          margin-right: 8px;
        }
        
        @keyframes jsi-spin {
          to { transform: rotate(360deg); }
        }
      `;
      
      const styleSheet = document.createElement('style');
      styleSheet.textContent = styles;
      document.head.appendChild(styleSheet);
    }

    render() {
      this.container.innerHTML = `
        <div class="jsi-widget">
          <div class="jsi-hero">
            <h1 class="jsi-title">Speed audit will never be the same again.</h1>
            <p class="jsi-subtitle">
              Get a comprehensive <strong>WordPress performance, SEO, and security audit</strong> powered by Google Lighthouse in seconds.
            </p>
            
            <form class="jsi-form" id="jsi-scan-form">
              <input 
                type="text" 
                id="jsi-url-input"
                class="jsi-input" 
                placeholder="your-wordpress-site.com"
                required
              />
              <button type="submit" class="jsi-button" id="jsi-scan-button">
                Get Started
              </button>
            </form>
            
            <div id="jsi-error-message" class="jsi-error" style="display: none;"></div>
            
            <div class="jsi-badges">
              <div class="jsi-badge">
                <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
                </svg>
                <span>Free forever</span>
              </div>
              <div class="jsi-badge">
                <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
                </svg>
                <span>No credit card</span>
              </div>
              <div class="jsi-badge">
                <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
                </svg>
                <span>Results in 60s</span>
              </div>
            </div>
          </div>
        </div>
      `;
    }

    attachEventListeners() {
      const form = document.getElementById('jsi-scan-form');
      const input = document.getElementById('jsi-url-input');
      const button = document.getElementById('jsi-scan-button');
      const errorDiv = document.getElementById('jsi-error-message');

      form.addEventListener('submit', async (e) => {
        e.preventDefault();
        
        let url = input.value.trim();
        if (!url) return;

        // Clean and normalize URL
        url = this.normalizeUrl(url);

        // Validate URL
        if (!this.isValidUrl(url)) {
          this.showError('Please enter a valid website URL');
          return;
        }

        // Hide previous errors
        errorDiv.style.display = 'none';

        // Update button state
        button.disabled = true;
        button.innerHTML = '<span class="jsi-spinner"></span>Analyzing...';

        try {
          console.log('Sending scan request to:', `${API_BASE_URL}/api/scan`);
          console.log('URL to scan:', url);
          
          const response = await fetch(`${API_BASE_URL}/api/scan`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({ url }),
          });

          console.log('Response status:', response.status);
          const data = await response.json();
          console.log('Response data:', data);

          if (data.jobId) {
            // Redirect to scanning page
            console.log('Redirecting to:', `${API_BASE_URL}/scanning/${data.jobId}`);
            window.location.href = `${API_BASE_URL}/scanning/${data.jobId}`;
          } else {
            throw new Error('No job ID received');
          }
        } catch (error) {
          console.error('JustSpeedIt Error:', error);
          this.showError('Failed to start scan. Please try again.');
          button.disabled = false;
          button.innerHTML = 'Get Started';
        }
      });
    }

    normalizeUrl(url) {
      // Remove whitespace
      url = url.trim();
      
      // Remove common prefixes that users might type
      url = url.replace(/^(www\.)/, '');
      
      // Add https:// if no protocol specified
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://' + url;
      }
      
      // Add www. back if the domain doesn't have a subdomain
      // (optional - you can remove this if you don't want it)
      try {
        const urlObj = new URL(url);
        // Only add www if hostname doesn't already have a subdomain
        if (!urlObj.hostname.includes('.', urlObj.hostname.indexOf('.') + 1)) {
          // This is a root domain, could add www but let's leave it as is
        }
      } catch (e) {
        // Invalid URL, will be caught by validation
      }
      
      return url;
    }

    isValidUrl(string) {
      try {
        const url = new URL(string);
        // Check if it's http or https
        if (url.protocol !== 'http:' && url.protocol !== 'https:') {
          return false;
        }
        // Check if hostname has at least one dot (e.g., example.com)
        if (!url.hostname.includes('.')) {
          return false;
        }
        return true;
      } catch (_) {
        return false;
      }
    }

    showError(message) {
      const errorDiv = document.getElementById('jsi-error-message');
      errorDiv.textContent = message;
      errorDiv.style.display = 'block';
    }
  }

  // Auto-initialize on DOM ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function() {
      new JustSpeedItWidget('justspeedit-widget');
    });
  } else {
    new JustSpeedItWidget('justspeedit-widget');
  }

  // Expose to window for manual initialization
  window.JustSpeedItWidget = JustSpeedItWidget;
})();

