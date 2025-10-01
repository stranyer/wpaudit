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
app.use(cors({
  origin: ['http://localhost:3000', 'http://wpaudit.test:3000', 'http://wpaudit.test'],
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