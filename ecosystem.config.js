module.exports = {
  apps: [
    {
      name: 'api',
      cwd: '/app/api',
      script: 'dist/index.js',
      env: {
        NODE_ENV: 'production',
        PORT: 3001
      }
    },
    {
      name: 'frontend',
      cwd: '/app/frontend',
      script: 'node_modules/next/dist/bin/next',
      args: 'start -p 3000',
      env: {
        NODE_ENV: 'production',
        PORT: 3000,
        NEXT_PUBLIC_API_URL: 'http://localhost:3001'
      }
    }
  ]
}
