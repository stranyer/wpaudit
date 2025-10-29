# Just Speed It - Deployment Guide for Koyeb

## Prerequisites
- GitHub account
- Koyeb account (free tier)
- Domain from Hostinger

## Step-by-Step Deployment

### 1. Push to GitHub

First, make sure your code is in a GitHub repository:

```bash
git init
git add .
git commit -m "Initial commit - Ready for Koyeb deployment"
git branch -M main
git remote add origin YOUR_GITHUB_REPO_URL
git push -u origin main
```

### 2. Deploy on Koyeb

1. **Login to Koyeb**: https://app.koyeb.com/
2. **Click "Create App"**
3. **Select "GitHub"** as deployment method
4. **Connect your GitHub account** and select the repository
5. **Configure the service**:
   - **Builder**: Docker
   - **Dockerfile path**: `Dockerfile`
   - **Port**: `3000` (frontend port)
   - **Health check path**: `/`
   
6. **Add Environment Variables**:
   - `NODE_ENV`: `production`
   - `NEXT_PUBLIC_API_URL`: `http://localhost:3001`
   
7. **Resources**:
   - Use the **Free tier** (0.5 GB RAM, 1 vCPU)
   
8. **Click "Deploy"**

### 3. Monitor Deployment

- Wait 5-10 minutes for the build to complete
- Check the logs to ensure everything is running
- Test the URL provided by Koyeb (e.g., `https://your-app.koyeb.app`)

### 4. Connect Your Hostinger Domain

Once your app is running on Koyeb:

1. **Get your Koyeb app URL** (e.g., `your-app.koyeb.app`)

2. **Login to Hostinger DNS Management**:
   - Go to Hostinger Dashboard
   - Select your domain
   - Go to "DNS / Name Servers"

3. **Add/Update DNS Records**:
   ```
   Type: CNAME
   Name: @
   Value: your-app.koyeb.app
   TTL: 3600
   ```
   
   ```
   Type: CNAME
   Name: www
   Value: your-app.koyeb.app
   TTL: 3600
   ```

4. **Wait for DNS propagation** (5 minutes - 24 hours, usually ~1 hour)

5. **Add Custom Domain in Koyeb**:
   - Go to your app settings in Koyeb
   - Click "Domains"
   - Add your custom domain
   - Enable SSL (automatic with Let's Encrypt)

### 5. Test Your Application

Visit your domain and test:
- Homepage loads correctly
- Can start a scan
- Scan completes and shows report
- Screenshots are visible

## Troubleshooting

### Build fails with "Out of memory"
- The free tier might be too small for Lighthouse
- Consider upgrading to a paid plan or use Railway instead

### Chromium fails to launch
- Check logs for Chromium errors
- Ensure the Dockerfile installs all required dependencies

### API not responding
- Check that both services are running in PM2
- Verify port 3001 is accessible internally
- Check PM2 logs: `pm2 logs`

### Screenshots not saving
- Ensure `/app/api/screenshots` directory has write permissions
- Check if volume storage is sufficient

## Environment Variables Reference

| Variable | Description | Example |
|----------|-------------|---------|
| `NODE_ENV` | Node environment | `production` |
| `NEXT_PUBLIC_API_URL` | API URL for frontend | `http://localhost:3001` |
| `PORT` | Frontend port | `3000` |

## Architecture

```
Koyeb Container
├── Frontend (Next.js) - Port 3000
│   └── Serves web interface
└── Backend (Express API) - Port 3001
    └── Runs Lighthouse scans with Chromium
```

## Support

If you encounter issues:
1. Check Koyeb logs
2. Verify all environment variables are set
3. Test locally with Docker: `docker build -t wpaudit . && docker run -p 3000:3000 wpaudit`

## Alternative: Railway Deployment

If Koyeb's free tier is insufficient, consider Railway:
- More resources available
- Better for Lighthouse scans
- ~$5-10/month
