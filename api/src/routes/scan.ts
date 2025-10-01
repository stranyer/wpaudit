import express from 'express'
import { v4 as uuidv4 } from 'uuid'
import scanService from '../services/scanService'

const router = express.Router()

// Start a new scan
router.post('/', async (req, res) => {
  try {
    console.log('📥 Scan request received:', req.body)
    console.log('🔍 scanService available:', !!scanService)
    console.log('🔍 scanService.startScan available:', !!scanService?.startScan)
    const { url } = req.body
    
    if (!url) {
      console.log('❌ No URL provided')
      return res.status(400).json({ error: 'URL is required' })
    }

    console.log('🔍 Validating URL:', url)
    // Validate URL
    try {
      new URL(url)
    } catch {
      console.log('❌ Invalid URL format:', url)
      return res.status(400).json({ error: 'Invalid URL format' })
    }

    // Start scan in background
    console.log('🚀 Starting scan service for URL:', url)
    const result = await scanService.startScan(url)
    
    const response = { 
      jobId: result.jobId,
      status: result.status,
      message: result.message
    }
    console.log('✅ Sending response:', response)
    
    res.json(response)
  } catch (error) {
    console.error('❌ Error starting scan:', error)
    res.status(500).json({ error: 'Internal server error' })
  }
})

// Get scan status
router.get('/:jobId', async (req, res) => {
  try {
    const { jobId } = req.params
    
    try {
      const status = await scanService.getScanStatus(jobId)
      res.json(status)
    } catch (error: any) {
      if (error.message === 'Scan not found') {
        return res.status(404).json({ error: 'Scan not found' })
      }
      throw error
    }
  } catch (error) {
    console.error('Error getting scan status:', error)
    res.status(500).json({ error: 'Internal server error' })
  }
})

export { router as scanRoutes }