# Just Speed It - WordPress Performance Audit Tool

> Audit your WordPress site. Fix what actually slows you down. A PageSpeed score won't pay your bills. Faster sites do.

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy)

---

## 🚀 Features

### Core Functionality
- ✅ **Google Lighthouse Integration** - Real performance scores (mobile + desktop)
- ✅ **WordPress Detection** - Automatic detection of WP version, theme, plugins
- ✅ **Core Web Vitals** - LCP, CLS, INP, FCP, TBT analysis
- ✅ **Security Analysis** - Vulnerabilities, outdated plugins, security headers
- ✅ **SEO Analysis** - Meta tags, headings, Open Graph, Schema.org
- ✅ **Accessibility Check** - WCAG compliance basics
- ✅ **GDPR Compliance** - Privacy policy, cookies, tracking detection

### Advanced Features
- ✅ **Screenshots** - Mobile + Desktop thumbnails + filmstrip
- ✅ **Optimization Opportunities** - Top 10 Lighthouse savings with estimates
- ✅ **Revenue Loss Calculator** - Interactive calculator showing $ impact
- ✅ **Share Results** - Twitter, LinkedIn, embeddable badges
- ✅ **Real-time Progress** - Live updates with fun facts during scan
- ✅ **Public Reports** - Shareable URLs with Open Graph meta tags

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|-----------|
| **Frontend** | Next.js 14, TypeScript, Tailwind CSS, shadcn/ui |
| **Backend** | Node.js, Express, TypeScript |
| **Analysis** | Google Lighthouse, Puppeteer, Cheerio |
| **Performance** | Worker Threads (non-blocking Lighthouse) |
| **Deployment** | Render.com (Free tier) |

---

## ⚡ Quick Start (Local Development)

### Prerequisites
- Node.js 18+
- npm or yarn
- Git

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/wpaudit.git
cd wpaudit

# Install dependencies
npm install

# Install frontend dependencies
cd frontend && npm install && cd ..

# Install API dependencies
cd api && npm install && cd ..

# Start development servers
npm run dev
```

This will start:
- Frontend: http://localhost:3000
- API: http://localhost:3001

---

## 🌐 Production Deployment (Render.com)

### Why Render.com?
- ✅ **100% FREE** tier (750 hours/month)
- ✅ **Chromium included** (Lighthouse works out-of-the-box)
- ✅ **Auto-deploy** from GitHub/GitLab
- ✅ **SSL included** (free Let's Encrypt)
- ✅ **Custom domain** support (free)

### Deploy in 15 Minutes

**Full guides**:
- [RENDER_DEPLOY.md](./RENDER_DEPLOY.md) - GitHub version
- [GITLAB_RENDER_DEPLOY.md](./GITLAB_RENDER_DEPLOY.md) - GitLab version

**Quick steps**:

1. Push to GitHub or GitLab
2. Connect to Render.com
3. Configure cron-job.org (keep app awake)
4. Add custom domain

**Setup cron job**: See [CRON_SETUP.md](./CRON_SETUP.md)

---

## 📁 Project Structure

```
wpaudit/
├── frontend/               # Next.js frontend
│   ├── app/               # Next.js 14 App Router
│   │   ├── page.tsx       # Landing page
│   │   ├── scanning/      # Progress page
│   │   └── report/        # Report page
│   ├── components/        # shadcn/ui components
│   └── lib/               # Utilities
│
├── api/                   # Express API
│   ├── src/
│   │   ├── index.ts       # API entry point
│   │   ├── routes/        # API routes
│   │   ├── services/      # Business logic
│   │   │   ├── scanService.ts    # Main scan orchestration
│   │   │   └── reportService.ts  # Report generation
│   │   └── utils/
│   │       ├── lighthouseRunner.ts  # Lighthouse Worker Thread
│   │       └── logger.ts            # Debug logging
│   └── screenshots/       # Generated screenshots
│
├── RENDER_DEPLOY.md       # Render.com deployment guide
├── CRON_SETUP.md          # Cron job configuration
├── DEPLOYMENT.md          # General deployment options
├── ROADMAP.md             # Future improvements
└── start-dev.js           # Development server launcher
```

---

## 🎯 Usage

1. **Enter URL**: Visit your deployed site
2. **Start Scan**: Enter any WordPress URL
3. **Watch Progress**: Real-time updates with fun facts
4. **View Report**: Comprehensive audit with scores
5. **Share Results**: Tweet, LinkedIn, or embed badge

---

## 📊 What Gets Analyzed?

### Performance (Lighthouse)
- Mobile & Desktop scores
- Core Web Vitals (LCP, CLS, INP)
- Time to Interactive, First Contentful Paint
- Total Blocking Time, Speed Index
- **Top 10 optimization opportunities** with savings

### WordPress
- Version detection
- Theme identification
- Plugin detection (Elementor, WooCommerce, Yoast, etc.)
- Outdated components

### Security
- XML-RPC exposure
- WordPress version leaks
- Security headers (CSP, X-Frame-Options, etc.)
- Known vulnerabilities

### SEO
- Meta tags (title, description)
- Open Graph & Twitter Cards
- Schema.org markup
- Heading structure
- Alt text on images

### Accessibility
- ARIA attributes
- Color contrast
- Form labels
- Focus indicators

### GDPR
- Privacy policy detection
- Cookie notices
- Contact information
- Tracking scripts (GA, FB Pixel, etc.)

---

## 💰 Revenue Loss Calculator

Interactive calculator showing:
- Monthly revenue loss
- Yearly impact
- Lost conversions
- Bounce rate increase
- Recovery potential

Based on industry research:
- Amazon: 100ms delay = 1% sales loss
- Google: 2s load time = 32% bounce rate increase

---

## 🔐 Environment Variables

### Frontend (.env.local)
```env
NEXT_PUBLIC_API_URL=https://your-api-domain.com
```

### API (.env)
```env
NODE_ENV=production
PORT=3001
FRONTEND_URL=https://your-domain.com
```

---

## 🚧 Roadmap

See [ROADMAP.md](./ROADMAP.md) for detailed future plans.

**Completed (95%)**:
- ✅ Lighthouse integration
- ✅ Screenshots & filmstrip
- ✅ Optimization opportunities
- ✅ Revenue calculator
- ✅ Share buttons
- ✅ Progress page improvements

**Planned**:
- ⏳ Redis caching (24h)
- ⏳ Comparison with industry average
- ⏳ PDF export
- ⏳ Historical tracking
- ⏳ Competitor benchmarking

---

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit changes (`git commit -m 'Add AmazingFeature'`)
4. Push to branch (`git push origin feature/AmazingFeature`)
5. Open Pull Request

---

## 📝 License

MIT License - see [LICENSE](LICENSE) file for details

---

## 🙏 Acknowledgments

- **Google Lighthouse** - Performance analysis engine
- **shadcn/ui** - Beautiful UI components
- **Next.js** - React framework
- **Render.com** - Free hosting platform
- **RapidLoad.ai** - UI inspiration

---

## 📞 Support

- **Issues**: https://github.com/yourusername/wpaudit/issues
- **Discussions**: https://github.com/yourusername/wpaudit/discussions
- **Email**: support@justspeedit.com

---

## 📈 Stats

- **Lines of Code**: 21,000+
- **Files**: 45
- **Commits**: 4+
- **Features**: 95% Complete
- **Deployment Time**: 15 minutes
- **Monthly Cost**: $0 (with Render free tier)

---

**Built with ❤️ for the WordPress community**

Deploy your own: [![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy)
