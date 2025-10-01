#!/bin/bash

# Just Audit It - Production Deployment Script
# chmod +x deploy.sh && ./deploy.sh

echo "🚀 Starting deployment..."

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Stop on error
set -e

echo -e "${YELLOW}📦 Installing dependencies...${NC}"
npm install

echo -e "${YELLOW}🔧 Building API...${NC}"
cd api
npm install
npm run build
cd ..

echo -e "${YELLOW}🎨 Building Frontend...${NC}"
cd frontend
npm install
npm run build
cd ..

echo -e "${YELLOW}🔄 Restarting services...${NC}"

# Check if PM2 is installed
if command -v pm2 &> /dev/null
then
    echo "Using PM2..."
    pm2 restart ecosystem.config.js
else
    echo -e "${RED}⚠️  PM2 not installed. Install with: npm install -g pm2${NC}"
    echo "Starting with Node.js instead..."
    
    # Kill existing processes
    pkill -f "node.*api" || true
    pkill -f "next" || true
    
    # Start API
    cd api && npm start &
    cd ..
    
    # Start Frontend
    cd frontend && npm start &
    cd ..
fi

echo -e "${GREEN}✅ Deployment complete!${NC}"
echo ""
echo "🌐 Frontend: http://localhost:3000"
echo "🔌 API: http://localhost:3001"
echo ""
echo "📊 Check status: pm2 status"
echo "📝 View logs: pm2 logs"

