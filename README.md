# 🚀 Just Speed It - WordPress Performance Auditor

> Comprehensive WordPress performance, SEO, and security auditing powered by Google Lighthouse

## 📋 Features

- ⚡ **Performance Analysis** - Core Web Vitals (LCP, CLS, INP)
- 🔒 **Security Scanning** - WordPress-specific vulnerabilities
- 📈 **SEO Analysis** - Meta tags, structured data, Open Graph
- 🔍 **WordPress Detection** - Theme, plugins, version
- 📊 **Detailed Reports** - Actionable insights and optimization tips
- 🌐 **Widget Integration** - Embeddable in any WordPress site

## 🛠️ Tech Stack

- **Frontend**: Next.js 14, React, Tailwind CSS
- **Backend**: Node.js, Express, TypeScript
- **Performance**: Google Lighthouse, Puppeteer
- **Deployment**: Railway (Docker)

## 🚀 Quick Start

### Prerequisites

- Node.js 20+
- npm or yarn

### Installation

```bash
# Clone the repository
git clone <your-repo-url>
cd wpaudit

# Install dependencies
npm install

# Install API dependencies
cd api
npm install

# Install Frontend dependencies
cd ../frontend
npm install
```

### Development

```bash
# Terminal 1: Start API (port 3001)
cd api
npm run dev

# Terminal 2: Start Frontend (port 3000)
cd frontend
npm run dev
```

Visit: `http://localhost:3000`

## 📦 Deployment (Railway)

### Auto-Deploy from Git

1. Connect your repository to Railway
2. Railway will auto-detect the Dockerfile
3. Set environment variables (if needed)
4. Deploy!

### Manual Deploy

```bash
git add .
git commit -m "your message"
git push origin main
```

Railway will automatically build and deploy.

## 🔧 Environment Variables

### Backend (API)

```env
PORT=3001
NODE_ENV=production
```

### Frontend

```env
NEXT_PUBLIC_API_URL=https://your-app.up.railway.app
PORT=3000
```

## 📖 Widget Integration (WordPress)

Add this to your WordPress site:

```html
<div id="justspeedit-widget"></div>
<script>
  window.JUSTSPEEDIT_API_URL = 'https://your-app.up.railway.app';
</script>
<script src="https://your-app.up.railway.app/api/widget" defer></script>
```

For detailed WordPress integration, see `WORDPRESS-INTEGRATION.md`

## 📊 How It Works

1. **Input**: User enters a WordPress URL
2. **Analysis**: 
   - Lighthouse audit (mobile + desktop)
   - WordPress fingerprinting
   - Security checks
   - SEO analysis
3. **Report**: Comprehensive report with:
   - Performance scores
   - Core Web Vitals
   - Optimization opportunities
   - WordPress-specific insights

## 🏗️ Project Structure

```
wpaudit/
├── api/                    # Backend API
│   ├── src/
│   │   ├── routes/        # API routes
│   │   ├── services/      # Business logic
│   │   └── utils/         # Lighthouse runner, etc.
│   └── package.json
├── frontend/              # Next.js frontend
│   ├── app/
│   │   ├── api/          # Next.js API routes (proxies)
│   │   ├── report/       # Report page
│   │   ├── scanning/     # Scanning progress page
│   │   └── page.tsx      # Landing page
│   ├── public/
│   │   ├── widget.js     # Embeddable widget
│   │   └── widget-test.html  # Test page
│   └── package.json
├── Dockerfile            # Production build
├── ecosystem.config.js   # PM2 config
├── railway.toml         # Railway config
└── README.md
```

## 📝 Key Files

- `api/src/utils/lighthouseRunner.ts` - Lighthouse configuration (exact PageSpeed Insights settings)
- `api/src/services/scanService.ts` - Main scanning logic
- `frontend/public/widget.js` - Embeddable widget
- `frontend/app/page.tsx` - Landing page
- `frontend/app/report/[reportId]/page.tsx` - Report viewer

## 🧪 Testing

### Test Widget Locally

Open: `http://localhost:3000/widget-test.html`

### Test Full Flow

1. Go to `http://localhost:3000`
2. Enter a WordPress URL (e.g., `wordpress.org`)
3. Wait for scan to complete
4. View report

### Compare with PageSpeed Insights

1. Scan a site in Just Speed It
2. Scan the same site at https://pagespeed.web.dev/
3. Compare scores (should be ±3 points)

## 🔍 Troubleshooting

### Port already in use

```bash
# Windows
Get-Process -Id (Get-NetTCPConnection -LocalPort 3000).OwningProcess | Stop-Process

# Linux/Mac
lsof -ti:3000 | xargs kill
```

### Build errors

```bash
# Clean and rebuild
rm -rf node_modules
rm -rf frontend/node_modules
rm -rf api/node_modules
npm install
cd api && npm install
cd ../frontend && npm install
```

## 📄 License

MIT

## 🤝 Contributing

Contributions welcome! Please open an issue first to discuss changes.

## 📞 Support

For issues or questions, open a GitHub issue.

---

Made with ⚡ by Just Speed It
