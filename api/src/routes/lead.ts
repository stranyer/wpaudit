import express from 'express'
import { leadService } from '../services/leadService'

const router = express.Router()

// Create lead
router.post('/', async (req, res) => {
  try {
    const { name, email, company, url, scanId, source } = req.body
    
    if (!email) {
      return res.status(400).json({ error: 'Email is required' })
    }

    const lead = await leadService.createLead({
      name,
      email,
      company,
      url,
      scanId,
      source: source || 'website'
    })
    
    res.json({ 
      success: true,
      leadId: lead.id,
      message: 'Lead created successfully'
    })
  } catch (error) {
    console.error('Error creating lead:', error)
    res.status(500).json({ error: 'Internal server error' })
  }
})

export { router as leadRoutes }