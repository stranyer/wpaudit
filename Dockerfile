# Multi-stage build for production

# Stage 1: Build API
FROM node:18-alpine AS api-builder
WORKDIR /app/api
COPY api/package*.json ./
RUN npm ci --only=production
COPY api/ ./
RUN npm run build

# Stage 2: Build Frontend
FROM node:18-alpine AS frontend-builder
WORKDIR /app/frontend
COPY frontend/package*.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build

# Stage 3: Production - API with Chromium
FROM node:18-alpine AS production

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

# Copy API built files
COPY --from=api-builder /app/api/dist ./api/dist
COPY --from=api-builder /app/api/node_modules ./api/node_modules
COPY --from=api-builder /app/api/package.json ./api/

# Copy Frontend built files
COPY --from=frontend-builder /app/frontend/.next ./frontend/.next
COPY --from=frontend-builder /app/frontend/node_modules ./frontend/node_modules
COPY --from=frontend-builder /app/frontend/package.json ./frontend/
COPY --from=frontend-builder /app/frontend/public ./frontend/public
COPY --from=frontend-builder /app/frontend/next.config.js ./frontend/

# Create screenshots directory
RUN mkdir -p /app/api/screenshots && chmod 777 /app/api/screenshots

# Install PM2 to run both services
RUN npm install -g pm2

# Copy PM2 ecosystem file
COPY ecosystem.config.js ./

# Expose ports
EXPOSE 3000 3001

# Start both services with PM2
CMD ["pm2-runtime", "start", "ecosystem.config.js"]
