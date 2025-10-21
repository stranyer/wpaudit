"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const worker_threads_1 = require("worker_threads");
const lighthouse_1 = __importDefault(require("lighthouse"));
const chromeLauncher = __importStar(require("chrome-launcher"));
const puppeteer_1 = __importDefault(require("puppeteer"));
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
// Use process.cwd() for compatibility with both CommonJS and ES modules
const projectRoot = process.cwd();
const screenshotsBaseDir = path_1.default.join(projectRoot, 'screenshots');
async function runLighthouse(task) {
    let chrome = null;
    try {
        // Get Puppeteer's Chromium executable path
        const executablePath = puppeteer_1.default.executablePath();
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
        });
        const options = {
            logLevel: 'error',
            output: 'json',
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
        };
        // Run Lighthouse
        const result = await (0, lighthouse_1.default)(task.url, options);
        if (!result || !result.lhr) {
            throw new Error('Lighthouse returned no results');
        }
        const metrics = result.lhr.audits;
        const score = result.lhr.categories?.performance?.score
            ? Math.round(result.lhr.categories.performance.score * 100)
            : 0;
        // Extract screenshot data
        const finalScreenshot = metrics['final-screenshot']?.details;
        const screenshotThumbnails = metrics['screenshot-thumbnails']?.details;
        // Save screenshots if available
        let screenshotPath = null;
        let filmstripFrames = [];
        if (task.jobId && finalScreenshot?.data) {
            try {
                const screenshotsDir = path_1.default.join(screenshotsBaseDir, task.jobId);
                if (!fs_1.default.existsSync(screenshotsDir)) {
                    fs_1.default.mkdirSync(screenshotsDir, { recursive: true });
                }
                // Save final screenshot
                const base64Data = finalScreenshot.data.replace(/^data:image\/\w+;base64,/, '');
                const buffer = Buffer.from(base64Data, 'base64');
                screenshotPath = path_1.default.join(screenshotsDir, `${task.formFactor}-final.jpg`);
                fs_1.default.writeFileSync(screenshotPath, buffer);
                // Save filmstrip frames
                if (screenshotThumbnails?.items) {
                    screenshotThumbnails.items.forEach((frame, index) => {
                        if (frame.data) {
                            const frameBase64 = frame.data.replace(/^data:image\/\w+;base64,/, '');
                            const frameBuffer = Buffer.from(frameBase64, 'base64');
                            const framePath = path_1.default.join(screenshotsDir, `${task.formFactor}-frame-${index}.jpg`);
                            fs_1.default.writeFileSync(framePath, frameBuffer);
                            filmstripFrames.push(framePath);
                        }
                    });
                }
            }
            catch (error) {
                console.error('Error saving screenshots:', error);
            }
        }
        // Extract opportunities (performance optimizations)
        const opportunities = [];
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
        ];
        opportunityAudits.forEach(auditKey => {
            const audit = metrics[auditKey];
            if (audit && audit.details && audit.numericValue > 0) {
                const details = audit.details;
                opportunities.push({
                    id: auditKey,
                    title: audit.title || auditKey,
                    description: audit.description || '',
                    savings: {
                        ms: audit.numericValue || 0,
                        bytes: details.overallSavingsBytes || 0
                    },
                    items: details.items?.slice(0, 5) || [] // Top 5 items
                });
            }
        });
        const data = {
            score,
            lcp: metrics['largest-contentful-paint']?.numericValue || 0,
            cls: metrics['cumulative-layout-shift']?.numericValue || 0,
            fcp: metrics['first-contentful-paint']?.numericValue || 0,
            si: metrics['speed-index']?.numericValue || 0,
            tbt: metrics['total-blocking-time']?.numericValue || 0,
            tti: metrics['interactive']?.numericValue || 0,
            ttfb: metrics['server-response-time']?.numericValue || 0,
            resourceSummary: metrics['resource-summary']?.details?.items?.[0] || {},
            screenshot: screenshotPath ? `/screenshots/${task.jobId}/${task.formFactor}-final.jpg` : null,
            filmstrip: filmstripFrames.map((frame, i) => `/screenshots/${task.jobId}/${task.formFactor}-frame-${i}.jpg`),
            opportunities: opportunities // Add opportunities
        };
        return data;
    }
    finally {
        if (chrome) {
            await chrome.kill();
        }
    }
}
// Worker thread message handler
if (worker_threads_1.parentPort) {
    worker_threads_1.parentPort.on('message', async (task) => {
        try {
            const result = await runLighthouse(task);
            worker_threads_1.parentPort.postMessage({ success: true, data: result });
        }
        catch (error) {
            worker_threads_1.parentPort.postMessage({ success: false, error: error.message });
        }
    });
}
