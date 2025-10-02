"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.reportRoutes = void 0;
const express_1 = __importDefault(require("express"));
const reportService_1 = require("../services/reportService");
const router = express_1.default.Router();
exports.reportRoutes = router;
// Get report by ID
router.get('/:reportId', async (req, res) => {
    try {
        const { reportId } = req.params;
        console.log('📋 Fetching report:', reportId);
        const report = await reportService_1.reportService.getReport(reportId);
        if (!report) {
            console.log('❌ Report not found:', reportId);
            return res.status(404).json({ error: 'Report not found' });
        }
        console.log('✅ Report found:', reportId);
        res.json(report);
    }
    catch (error) {
        console.error('Error getting report:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Get public report
router.get('/public/:publicId', async (req, res) => {
    try {
        const { publicId } = req.params;
        const report = await reportService_1.reportService.getPublicReport(publicId);
        if (!report) {
            return res.status(404).json({ error: 'Report not found' });
        }
        res.json(report);
    }
    catch (error) {
        console.error('Error getting public report:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
