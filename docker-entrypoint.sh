#!/bin/sh

# Start API in background
cd /app/api && node dist/index.js &

# Start Frontend (foreground)
cd /app/frontend && npm start

