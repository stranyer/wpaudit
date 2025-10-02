"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.pdfRoutes = void 0;
const express_1 = __importDefault(require("express"));
const puppeteer_extra_1 = __importDefault(require("puppeteer-extra"));
const puppeteer_extra_plugin_stealth_1 = __importDefault(require("puppeteer-extra-plugin-stealth"));
const reportService_1 = require("../services/reportService");
puppeteer_extra_1.default.use((0, puppeteer_extra_plugin_stealth_1.default)());
const router = express_1.default.Router();
exports.pdfRoutes = router;
// Generate PDF report
router.get('/:reportId', async (req, res) => {
    try {
        const { reportId } = req.params;
        const report = await reportService_1.reportService.getReport(reportId);
        if (!report) {
            return res.status(404).json({ error: 'Report not found' });
        }
        console.log('📄 Generating PDF for report:', reportId);
        // Generate PDF using Puppeteer
        const browser = await puppeteer_extra_1.default.launch({
            headless: true,
            args: ['--no-sandbox', '--disable-setuid-sandbox']
        });
        const page = await browser.newPage();
        // Create HTML content for PDF
        const htmlContent = generateReportHTML(report);
        await page.setContent(htmlContent, { waitUntil: 'networkidle0' });
        const pdfBuffer = await page.pdf({
            format: 'A4',
            printBackground: true,
            margin: {
                top: '20mm',
                right: '20mm',
                bottom: '20mm',
                left: '20mm'
            }
        });
        await browser.close();
        // Set headers for PDF download
        res.setHeader('Content-Type', 'application/pdf');
        res.setHeader('Content-Disposition', `attachment; filename="wordpress-audit-${reportId}.pdf"`);
        res.setHeader('Content-Length', pdfBuffer.length);
        res.send(pdfBuffer);
    }
    catch (error) {
        console.error('Error generating PDF:', error);
        res.status(500).json({ error: 'Failed to generate PDF' });
    }
});
function generateReportHTML(report) {
    const { data } = report;
    return `
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>WordPress Audit Report - ${report.url}</title>
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          line-height: 1.6;
          color: #333;
          max-width: 800px;
          margin: 0 auto;
          padding: 20px;
        }
        .header {
          text-align: center;
          border-bottom: 3px solid #3b82f6;
          padding-bottom: 20px;
          margin-bottom: 30px;
        }
        .logo {
          font-size: 28px;
          font-weight: bold;
          color: #3b82f6;
          margin-bottom: 10px;
        }
        .url {
          color: #666;
          font-size: 16px;
        }
        .date {
          color: #999;
          font-size: 14px;
        }
        .scores {
          display: grid;
          grid-template-columns: repeat(4, 1fr);
          gap: 20px;
          margin: 30px 0;
        }
        .score-card {
          text-align: center;
          padding: 20px;
          border: 2px solid #e5e7eb;
          border-radius: 8px;
          background: #f9fafb;
        }
        .score-number {
          font-size: 36px;
          font-weight: bold;
          margin-bottom: 5px;
        }
        .score-good { color: #10b981; }
        .score-warning { color: #f59e0b; }
        .score-bad { color: #ef4444; }
        .score-label {
          font-size: 14px;
          color: #666;
          text-transform: uppercase;
          letter-spacing: 0.5px;
        }
        .section {
          margin: 40px 0;
        }
        .section-title {
          font-size: 24px;
          font-weight: bold;
          color: #1f2937;
          margin-bottom: 20px;
          border-bottom: 2px solid #e5e7eb;
          padding-bottom: 10px;
        }
        .metric {
          display: flex;
          justify-content: space-between;
          padding: 10px 0;
          border-bottom: 1px solid #f3f4f6;
        }
        .metric:last-child {
          border-bottom: none;
        }
        .metric-label {
          font-weight: 500;
        }
        .metric-value {
          color: #666;
        }
        .recommendations {
          background: #f8fafc;
          padding: 20px;
          border-radius: 8px;
          border-left: 4px solid #3b82f6;
        }
        .recommendation {
          margin: 15px 0;
          padding: 15px;
          background: white;
          border-radius: 6px;
          border: 1px solid #e5e7eb;
        }
        .recommendation-title {
          font-weight: bold;
          color: #1f2937;
          margin-bottom: 5px;
        }
        .recommendation-impact {
          display: inline-block;
          padding: 2px 8px;
          border-radius: 4px;
          font-size: 12px;
          font-weight: bold;
          text-transform: uppercase;
        }
        .impact-high { background: #fee2e2; color: #dc2626; }
        .impact-medium { background: #fef3c7; color: #d97706; }
        .impact-low { background: #d1fae5; color: #059669; }
        .footer {
          margin-top: 50px;
          text-align: center;
          color: #666;
          font-size: 14px;
          border-top: 1px solid #e5e7eb;
          padding-top: 20px;
        }
      </style>
    </head>
    <body>
      <div class="header">
        <div class="logo">Just Audit It</div>
        <div class="url">${report.url}</div>
        <div class="date">Audit completed on ${new Date(data.meta.scannedAt).toLocaleDateString()}</div>
      </div>
      
      <div class="scores">
        <div class="score-card">
          <div class="score-number ${getScoreClass(data.performance.scores.mobile)}">${data.performance.scores.mobile}</div>
          <div class="score-label">Performance</div>
        </div>
        <div class="score-card">
          <div class="score-number ${getScoreClass(data.seo.score)}">${data.seo.score}</div>
          <div class="score-label">SEO</div>
        </div>
        <div class="score-card">
          <div class="score-number ${getScoreClass(data.security.score)}">${data.security.score}</div>
          <div class="score-label">Security</div>
        </div>
        <div class="score-card">
          <div class="score-number ${getScoreClass(data.accessibility.score)}">${data.accessibility.score}</div>
          <div class="score-label">Accessibility</div>
        </div>
      </div>
      
      <div class="section">
        <div class="section-title">WordPress Information</div>
        <div class="metric">
          <span class="metric-label">WordPress Version</span>
          <span class="metric-value">${data.wordpress.version || 'Not detected'}</span>
        </div>
        <div class="metric">
          <span class="metric-label">Active Theme</span>
          <span class="metric-value">${data.wordpress.theme?.name || 'Not detected'}</span>
        </div>
        <div class="metric">
          <span class="metric-label">Plugins Detected</span>
          <span class="metric-value">${data.wordpress.plugins?.length || 0}</span>
        </div>
      </div>
      
      <div class="section">
        <div class="section-title">Performance Metrics</div>
        <div class="metric">
          <span class="metric-label">Largest Contentful Paint (LCP)</span>
          <span class="metric-value">${data.performance.coreWebVitals.lcp.toFixed(2)}s</span>
        </div>
        <div class="metric">
          <span class="metric-label">Cumulative Layout Shift (CLS)</span>
          <span class="metric-value">${data.performance.coreWebVitals.cls.toFixed(3)}</span>
        </div>
        <div class="metric">
          <span class="metric-label">Total Requests</span>
          <span class="metric-value">${data.performance.requests}</span>
        </div>
        <div class="metric">
          <span class="metric-label">Page Size</span>
          <span class="metric-value">${data.performance.transferMB.toFixed(2)} MB</span>
        </div>
      </div>
      
      <div class="section">
        <div class="section-title">SEO Analysis</div>
        <div class="metric">
          <span class="metric-label">Title Tag</span>
          <span class="metric-value">${data.seo.title.present ? 'Present' : 'Missing'} (${data.seo.title.length} chars)</span>
        </div>
        <div class="metric">
          <span class="metric-label">Meta Description</span>
          <span class="metric-value">${data.seo.metaDescription.present ? 'Present' : 'Missing'} (${data.seo.metaDescription.length} chars)</span>
        </div>
        <div class="metric">
          <span class="metric-label">H1 Tags</span>
          <span class="metric-value">${data.seo.headings.h1Count} (${data.seo.headings.hasSingleH1 ? 'Good' : 'Issues'})</span>
        </div>
        <div class="metric">
          <span class="metric-label">Images with Alt Text</span>
          <span class="metric-value">${data.seo.images.altPercentage}%</span>
        </div>
      </div>
      
      <div class="section">
        <div class="section-title">Security Analysis</div>
        <div class="metric">
          <span class="metric-label">XML-RPC</span>
          <span class="metric-value">${data.security.xmlrpc === 'open' ? '⚠️ Open' : '✅ Protected'}</span>
        </div>
        <div class="metric">
          <span class="metric-label">Security Headers</span>
          <span class="metric-value">${Object.values(data.security.headers).filter(Boolean).length}/6</span>
        </div>
        <div class="metric">
          <span class="metric-label">WordPress Version</span>
          <span class="metric-value">${data.security.wordpressVersion.exposed ? '⚠️ Exposed' : '✅ Hidden'}</span>
        </div>
      </div>
      
      <div class="section">
        <div class="section-title">Accessibility</div>
        <div class="metric">
          <span class="metric-label">Language Attribute</span>
          <span class="metric-value">${data.accessibility.lang ? '✅ Present' : '❌ Missing'}</span>
        </div>
        <div class="metric">
          <span class="metric-label">Form Labels</span>
          <span class="metric-value">${data.accessibility.forms.labelPercentage}%</span>
        </div>
        <div class="metric">
          <span class="metric-label">Image Alt Text</span>
          <span class="metric-value">${data.accessibility.images.altPercentage}%</span>
        </div>
      </div>
      
      <div class="section">
        <div class="section-title">GDPR Compliance</div>
        <div class="metric">
          <span class="metric-label">Privacy Policy</span>
          <span class="metric-value">${data.gdpr.privacyPolicy ? '✅ Present' : '❌ Missing'}</span>
        </div>
        <div class="metric">
          <span class="metric-label">Cookie Notice</span>
          <span class="metric-value">${data.gdpr.cookieNotice ? '✅ Present' : '❌ Missing'}</span>
        </div>
        <div class="metric">
          <span class="metric-label">Contact Information</span>
          <span class="metric-value">${data.gdpr.contactInfo ? '✅ Present' : '❌ Missing'}</span>
        </div>
      </div>
      
      <div class="section">
        <div class="section-title">Recommendations</div>
        <div class="recommendations">
          ${data.priorities.map((rec) => `
            <div class="recommendation">
              <div class="recommendation-title">${rec.title}</div>
              <div class="recommendation-impact impact-${rec.impact}">${rec.impact} impact</div>
              <div style="margin-top: 8px; color: #666;">${rec.why}</div>
            </div>
          `).join('')}
        </div>
      </div>
      
      <div class="footer">
        <p>Generated by Just Audit It - WordPress Performance & Security Audit Tool</p>
        <p>For more information, visit: <strong>${report.url}</strong></p>
      </div>
    </body>
    </html>
  `;
}
function getScoreClass(score) {
    if (score >= 90)
        return 'score-good';
    if (score >= 70)
        return 'score-warning';
    return 'score-bad';
}
