"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.scanRoutes = void 0;
const express_1 = __importDefault(require("express"));
const scanService_1 = __importDefault(require("../services/scanService"));
const router = express_1.default.Router();
exports.scanRoutes = router;
// Start a new scan
router.post('/', async (req, res) => {
    try {
        console.log('📥 Scan request received:', req.body);
        console.log('🔍 scanService available:', !!scanService_1.default);
        console.log('🔍 scanService.startScan available:', !!scanService_1.default?.startScan);
        const { url } = req.body;
        if (!url) {
            console.log('❌ No URL provided');
            return res.status(400).json({ error: 'URL is required' });
        }
        console.log('🔍 Validating URL:', url);
        // Validate URL
        try {
            new URL(url);
        }
        catch {
            console.log('❌ Invalid URL format:', url);
            return res.status(400).json({ error: 'Invalid URL format' });
        }
        // Start scan in background
        console.log('🚀 Starting scan service for URL:', url);
        const result = await scanService_1.default.startScan(url);
        const response = {
            jobId: result.jobId,
            status: result.status,
            message: result.message
        };
        console.log('✅ Sending response:', response);
        res.json(response);
    }
    catch (error) {
        console.error('❌ Error starting scan:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Get scan status
router.get('/:jobId', async (req, res) => {
    try {
        const { jobId } = req.params;
        try {
            const status = await scanService_1.default.getScanStatus(jobId);
            res.json(status);
        }
        catch (error) {
            if (error.message === 'Scan not found') {
                return res.status(404).json({ error: 'Scan not found' });
            }
            throw error;
        }
    }
    catch (error) {
        console.error('Error getting scan status:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
