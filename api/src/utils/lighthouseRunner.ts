import { parentPort } from 'worker_threads'
import lighthouse from 'lighthouse'
import * as chromeLauncher from 'chrome-launcher'
import puppeteer from 'puppeteer'
import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'

// Fix for __dirname in ES modules
const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

interface LighthouseTask {
  url: string
  formFactor: 'mobile' | 'desktop'
  jobId?: string
}

async function runLighthouse(task: LighthouseTask) {
  let chrome: any = null
  
  try {
    // Get Puppeteer's Chromium executable path
    const executablePath = puppeteer.executablePath()
    
    // Launch Chrome using Puppeteer's Chromium
    chrome = await chromeLauncher.launch({
      chromePath: executablePath,
      chromeFlags: [
        '--headless=new',
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-gpu',
        '--no-first-run',
        '--disable-default-apps',
        '--disable-extensions'
      ]
    })

    const options = {
      logLevel: 'error' as const,
      output: 'json' as const,
      onlyCategories: ['performance'],
      port: chrome.port,
      formFactor: task.formFactor,
      screenEmulation: {
        mobile: task.formFactor === 'mobile',
        width: task.formFactor === 'mobile' ? 375 : 1350,
        height: task.formFactor === 'mobile' ? 667 : 940,
        deviceScaleFactor: task.formFactor === 'mobile' ? 2 : 1,
        disabled: false
      },
      throttling: task.formFactor === 'mobile' 
        ? {
            rttMs: 150,
            throughputKbps: 1638.4,
            requestLatencyMs: 150 * 3.75,
            downloadThroughputKbps: 1638.4,
            uploadThroughputKbps: 675,
            cpuSlowdownMultiplier: 4
          }
        : {
            rttMs: 40,
            throughputKbps: 10240,
            requestLatencyMs: 0,
            downloadThroughputKbps: 0,
            uploadThroughputKbps: 0,
            cpuSlowdownMultiplier: 1
          },
      throttlingMethod: 'simulate'
    }

    // Run Lighthouse
    const result = await lighthouse(task.url, options)

    if (!result || !result.lhr) {
      throw new Error('Lighthouse returned no results')
    }

    const metrics = result.lhr.audits
    const score = result.lhr.categories?.performance?.score 
      ? Math.round(result.lhr.categories.performance.score * 100) 
      : 0

    // Extract screenshot data
    const finalScreenshot = metrics['final-screenshot']?.details as any
    const screenshotThumbnails = metrics['screenshot-thumbnails']?.details as any
    
    // Save screenshots if available
    let screenshotPath = null
    let filmstripFrames: string[] = []
    
    if (task.jobId && finalScreenshot?.data) {
      try {
        const screenshotsDir = path.join(__dirname, '../../screenshots', task.jobId)
        if (!fs.existsSync(screenshotsDir)) {
          fs.mkdirSync(screenshotsDir, { recursive: true })
        }
        
        // Save final screenshot
        const base64Data = finalScreenshot.data.replace(/^data:image\/\w+;base64,/, '')
        const buffer = Buffer.from(base64Data, 'base64')
        screenshotPath = path.join(screenshotsDir, `${task.formFactor}-final.jpg`)
        fs.writeFileSync(screenshotPath, buffer)
        
        // Save filmstrip frames
        if (screenshotThumbnails?.items) {
          screenshotThumbnails.items.forEach((frame: any, index: number) => {
            if (frame.data) {
              const frameBase64 = frame.data.replace(/^data:image\/\w+;base64,/, '')
              const frameBuffer = Buffer.from(frameBase64, 'base64')
              const framePath = path.join(screenshotsDir, `${task.formFactor}-frame-${index}.jpg`)
              fs.writeFileSync(framePath, frameBuffer)
              filmstripFrames.push(framePath)
            }
          })
        }
      } catch (error) {
        console.error('Error saving screenshots:', error)
      }
    }

    // Extract opportunities (performance optimizations)
    const opportunities: any[] = []
    const opportunityAudits = [
      'offscreen-images',
      'uses-optimized-images',
      'modern-image-formats',
      'unminified-css',
      'unminified-javascript',
      'unused-css-rules',
      'unused-javascript',
      'uses-text-compression',
      'uses-responsive-images',
      'efficient-animated-content',
      'duplicated-javascript',
      'legacy-javascript',
      'total-byte-weight',
      'render-blocking-resources'
    ]

    opportunityAudits.forEach(auditKey => {
      const audit = metrics[auditKey]
      if (audit && audit.details && audit.numericValue > 0) {
        const details = audit.details as any
        opportunities.push({
          id: auditKey,
          title: audit.title || auditKey,
          description: audit.description || '',
          savings: {
            ms: audit.numericValue || 0,
            bytes: details.overallSavingsBytes || 0
          },
          items: details.items?.slice(0, 5) || [] // Top 5 items
        })
      }
    })

    const data = {
      score,
      lcp: metrics['largest-contentful-paint']?.numericValue || 0,
      cls: metrics['cumulative-layout-shift']?.numericValue || 0,
      fcp: metrics['first-contentful-paint']?.numericValue || 0,
      si: metrics['speed-index']?.numericValue || 0,
      tbt: metrics['total-blocking-time']?.numericValue || 0,
      tti: metrics['interactive']?.numericValue || 0,
      ttfb: metrics['server-response-time']?.numericValue || 0,
      resourceSummary: (metrics['resource-summary']?.details as any)?.items?.[0] || {},
      screenshot: screenshotPath ? `/screenshots/${task.jobId}/${task.formFactor}-final.jpg` : null,
      filmstrip: filmstripFrames.map((frame, i) => `/screenshots/${task.jobId}/${task.formFactor}-frame-${i}.jpg`),
      opportunities: opportunities // Add opportunities
    }

    return data
  } finally {
    if (chrome) {
      await chrome.kill()
    }
  }
}

// Worker thread message handler
if (parentPort) {
  parentPort.on('message', async (task: LighthouseTask) => {
    try {
      const result = await runLighthouse(task)
      parentPort!.postMessage({ success: true, data: result })
    } catch (error: any) {
      parentPort!.postMessage({ success: false, error: error.message })
    }
  })
}
