import express from 'express'
import cors from 'cors'
import helmet from 'helmet'
import path from 'path'
import { scanRoutes } from './routes/scan'
import { reportRoutes } from './routes/report'
import { leadRoutes } from './routes/lead'
import { pdfRoutes } from './routes/pdf'

const app = express()
const PORT = process.env.PORT || 3001

// Middleware
app.use(helmet({
  crossOriginResourcePolicy: { policy: "cross-origin" }
}))
// Configure CORS to allow requests from WordPress and local development
const allowedOrigins = [
  'http://localhost:3000',
  'http://wpaudit.test:3000',
  'http://wpaudit.test',
  'https://justspeedit.com',
  'http://justspeedit.com',
  'https://www.justspeedit.com',
  'http://www.justspeedit.com'
]

app.use(cors({
  origin: function (origin, callback) {
    // Allow requests with no origin (like mobile apps or curl)
    if (!origin) return callback(null, true)
    
    if (allowedOrigins.indexOf(origin) !== -1) {
      callback(null, true)
    } else {
      // For development, allow all origins
      if (process.env.NODE_ENV !== 'production') {
        callback(null, true)
      } else {
        callback(new Error('Not allowed by CORS'))
      }
    }
  },
  credentials: true
}))
app.use(express.json())

// Static files - Screenshots
app.use('/screenshots', express.static(path.join(__dirname, '../screenshots')))

// Routes
app.use('/api/scan', scanRoutes)
app.use('/api/report', reportRoutes)
app.use('/api/lead', leadRoutes)
app.use('/api/pdf', pdfRoutes)

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() })
})

app.listen(PORT, () => {
  console.log(`🚀 API server running on port ${PORT}`)
  console.log(`📊 Health check: http://localhost:${PORT}/health`)
})