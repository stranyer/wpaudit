# Use Node 20 for better compatibility
FROM node:20-alpine

# Install Chromium and dependencies for Lighthouse
RUN apk add --no-cache \
    chromium \
    nss \
    freetype \
    harfbuzz \
    ca-certificates \
    ttf-freefont

# Tell Puppeteer to use installed Chromium
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser \
    NODE_ENV=production

# Create app directory
WORKDIR /app

# Copy package files
COPY api/package*.json ./api/
COPY frontend/package*.json ./frontend/

# Install dependencies
WORKDIR /app/api
RUN npm ci --only=production

WORKDIR /app/frontend
RUN npm ci

# Copy source files
WORKDIR /app
COPY api/ ./api/
COPY frontend/ ./frontend/

# Build API
WORKDIR /app/api
RUN npm run build

# Build Frontend
WORKDIR /app/frontend
RUN npm run build

# Create screenshots directory
WORKDIR /app
RUN mkdir -p /app/api/screenshots && chmod 777 /app/api/screenshots

# Install PM2 to run both services
RUN npm install -g pm2

# Copy PM2 ecosystem file
COPY ecosystem.config.js ./

# Expose ports
EXPOSE 3000 3001

# Start both services with PM2
CMD ["pm2-runtime", "start", "ecosystem.config.js"]
