import express from 'express'
import { reportService } from '../services/reportService'

const router = express.Router()

// Get report by ID
router.get('/:reportId', async (req, res) => {
  try {
    const { reportId } = req.params
    console.log('📋 Fetching report:', reportId)
    const report = await reportService.getReport(reportId)
    
    if (!report) {
      console.log('❌ Report not found:', reportId)
      return res.status(404).json({ error: 'Report not found' })
    }
    
    console.log('✅ Report found:', reportId)
    res.json(report)
  } catch (error) {
    console.error('Error getting report:', error)
    res.status(500).json({ error: 'Internal server error' })
  }
})

// Get public report
router.get('/public/:publicId', async (req, res) => {
  try {
    const { publicId } = req.params
    const report = await reportService.getPublicReport(publicId)
    
    if (!report) {
      return res.status(404).json({ error: 'Report not found' })
    }
    
    res.json(report)
  } catch (error) {
    console.error('Error getting public report:', error)
    res.status(500).json({ error: 'Internal server error' })
  }
})

export { router as reportRoutes }