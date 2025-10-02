"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.leadService = void 0;
class LeadService {
    constructor() {
        this.leads = new Map();
    }
    async createLead(data) {
        const lead = {
            id: this.generateId(),
            name: data.name,
            email: data.email,
            company: data.company,
            url: data.url,
            scanId: data.scanId,
            source: data.source || 'website',
            createdAt: new Date().toISOString()
        };
        this.leads.set(lead.id, lead);
        // TODO: Send to CRM (HubSpot, Close, etc.)
        console.log('Lead created:', lead);
        return lead;
    }
    async getLead(id) {
        return this.leads.get(id) || null;
    }
    generateId() {
        return Math.random().toString(36).substr(2, 9);
    }
}
exports.leadService = new LeadService();
