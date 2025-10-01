/** @type {import('next').NextConfig} */
const nextConfig = {
  experimental: {
    appDir: true,
  },
  async rewrites() {
    return [
      {
        source: '/api/:path*',
        destination: 'http://localhost:3001/api/:path*',
      },
    ]
  },
  // Allow external domains for Laragon
  images: {
    domains: ['localhost', 'wpaudit.test'],
  },
}

module.exports = nextConfig