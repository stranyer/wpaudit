# Just Audit It - Production Dockerfile
# Build: docker build -t wpaudit .
# Run: docker run -p 3000:3000 -p 3001:3001 wpaudit

FROM node:18-alpine AS base

# Install Chromium and dependencies for Lighthouse
RUN apk add --no-cache \
    chromium \
    nss \
    freetype \
    harfbuzz \
    ca-certificates \
    ttf-freefont

# Tell Puppeteer to skip installing Chrome, we'll use the installed package
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

WORKDIR /app

# Copy package files
COPY package*.json ./
COPY api/package*.json ./api/
COPY frontend/package*.json ./frontend/

# Install dependencies
RUN npm install
RUN cd api && npm install
RUN cd frontend && npm install

# Copy source code
COPY . .

# Build API
RUN cd api && npm run build

# Build Frontend
RUN cd frontend && npm run build

# Expose ports
EXPOSE 3000 3001

# Start script
COPY docker-entrypoint.sh /
RUN chmod +x /docker-entrypoint.sh

CMD ["/docker-entrypoint.sh"]

