interface Lead {
  id: string
  name?: string
  email: string
  company?: string
  url?: string
  scanId?: string
  source: string
  createdAt: string
}

class LeadService {
  private leads: Map<string, Lead> = new Map()

  async createLead(data: {
    name?: string
    email: string
    company?: string
    url?: string
    scanId?: string
    source?: string
  }): Promise<Lead> {
    const lead: Lead = {
      id: this.generateId(),
      name: data.name,
      email: data.email,
      company: data.company,
      url: data.url,
      scanId: data.scanId,
      source: data.source || 'website',
      createdAt: new Date().toISOString()
    }
    
    this.leads.set(lead.id, lead)
    
    // TODO: Send to CRM (HubSpot, Close, etc.)
    console.log('Lead created:', lead)
    
    return lead
  }

  async getLead(id: string): Promise<Lead | null> {
    return this.leads.get(id) || null
  }

  private generateId(): string {
    return Math.random().toString(36).substr(2, 9)
  }
}

export const leadService = new LeadService()
