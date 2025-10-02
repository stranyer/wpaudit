"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.leadRoutes = void 0;
const express_1 = __importDefault(require("express"));
const leadService_1 = require("../services/leadService");
const router = express_1.default.Router();
exports.leadRoutes = router;
// Create lead
router.post('/', async (req, res) => {
    try {
        const { name, email, company, url, scanId, source } = req.body;
        if (!email) {
            return res.status(400).json({ error: 'Email is required' });
        }
        const lead = await leadService_1.leadService.createLead({
            name,
            email,
            company,
            url,
            scanId,
            source: source || 'website'
        });
        res.json({
            success: true,
            leadId: lead.id,
            message: 'Lead created successfully'
        });
    }
    catch (error) {
        console.error('Error creating lead:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
