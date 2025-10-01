# Just Audit It - WordPress Performance & Security Audit Tool

A comprehensive WordPress audit tool that goes beyond PageSpeed Insights to provide actionable recommendations specifically for WordPress sites.

## Features

- **WordPress Detection**: Automatically detects WordPress sites, version, theme, and plugins
- **Performance Analysis**: Real Core Web Vitals analysis with Lighthouse integration
- **Security Scanning**: WordPress-specific security checks
- **SEO Analysis**: On-page SEO essentials
- **Plugin Fingerprinting**: Detects popular plugins and their performance impact
- **Actionable Reports**: Generates PDF reports with prioritized recommendations
- **Lead Generation**: Captures leads with automated email sequences

## Tech Stack

- **Frontend**: Next.js 14, TypeScript, Tailwind CSS, shadcn/ui
- **Backend**: Node.js, Express, TypeScript
- **Analysis**: Puppeteer, Lighthouse, Cheerio
- **Queue**: BullMQ with Redis
- **Database**: PostgreSQL (production)
- **Storage**: AWS S3 (for PDFs and screenshots)

## Quick Start

### Prerequisites

- Node.js 18+
- npm or yarn
- Redis (for job queue)
- Laragon (for local development)

### Installation

1. **Clone and install dependencies:**

```bash
# Install root dependencies
npm install

# Install frontend dependencies
cd frontend && npm install

# Install API dependencies
cd ../api && npm install
```

2. **Start Redis (required for job queue):**

```bash
# Using Docker
docker run -d -p 6379:6379 redis:alpine

# Or install Redis locally
# Windows: Use WSL or Docker
# macOS: brew install redis && brew services start redis
# Linux: sudo apt install redis-server
```

3. **Start development servers:**

```bash
# From root directory
npm run dev
```

This will start:
- Frontend: http://localhost:3000
- API: http://localhost:3001

### Development

The project uses a monorepo structure:

```
wpaudit/
├── frontend/          # Next.js frontend
│   ├── app/           # App router pages
│   ├── components/    # React components
│   └── lib/           # Utilities
├── api/               # Express API
│   ├── src/
│   │   ├── routes/    # API routes
│   │   ├── services/  # Business logic
│   │   └── index.ts   # Entry point
└── package.json       # Root package.json
```

### API Endpoints

- `POST /api/scan` - Start a new scan
- `GET /api/scan/:jobId` - Get scan status
- `GET /api/report/:reportId` - Get report by ID
- `GET /api/report/public/:publicId` - Get public report
- `POST /api/lead` - Create lead

### Environment Variables

Copy `env.example` to `.env` and configure:

```bash
cp env.example .env
```

Key variables:
- `API_PORT=3001`
- `REDIS_URL=redis://localhost:6379`
- `DATABASE_URL=postgresql://...` (for production)

## Architecture

### Scan Process

1. **URL Validation**: Validates input URL
2. **Page Analysis**: Downloads and analyzes HTML
3. **WordPress Detection**: Checks for WP indicators
4. **Performance Testing**: Runs Lighthouse analysis
5. **Plugin Detection**: Fingerprints plugins and themes
6. **Report Generation**: Creates actionable recommendations

### WordPress Detection

The tool detects WordPress through multiple indicators:
- Meta generator tag
- wp-content paths in HTML
- WordPress cookies
- wp-json API endpoints
- Theme and plugin fingerprints

### Plugin Fingerprinting

Detects popular plugins by analyzing:
- Asset paths (`/wp-content/plugins/{slug}/`)
- CSS/JS class names
- REST API endpoints
- HTML patterns

## Roadmap

### MVP (Current)
- [x] Basic project structure
- [x] Landing page with URL input
- [x] Scan API with job queue
- [x] WordPress detection
- [x] Lighthouse integration
- [ ] Report generation
- [ ] PDF export
- [ ] Lead capture

### V2 (4-8 weeks)
- [ ] Extended plugin catalog (50-150 plugins)
- [ ] WooCommerce-specific analysis
- [ ] SEO deep dive
- [ ] Multi-language support
- [ ] API documentation

### V3 (8-12 weeks)
- [ ] WordPress connector plugin
- [ ] Deep database analysis
- [ ] Before/after tracking
- [ ] Multi-site dashboard
- [ ] White-label options

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

MIT License - see LICENSE file for details.

## Support

For questions or support, please open an issue on GitHub.