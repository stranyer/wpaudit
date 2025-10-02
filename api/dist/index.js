"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const cors_1 = __importDefault(require("cors"));
const helmet_1 = __importDefault(require("helmet"));
const path_1 = __importDefault(require("path"));
const scan_1 = require("./routes/scan");
const report_1 = require("./routes/report");
const lead_1 = require("./routes/lead");
const pdf_1 = require("./routes/pdf");
const app = (0, express_1.default)();
const PORT = process.env.PORT || 3001;
// Middleware
app.use((0, helmet_1.default)({
    crossOriginResourcePolicy: { policy: "cross-origin" }
}));
app.use((0, cors_1.default)({
    origin: ['http://localhost:3000', 'http://wpaudit.test:3000', 'http://wpaudit.test'],
    credentials: true
}));
app.use(express_1.default.json());
// Static files - Screenshots
app.use('/screenshots', express_1.default.static(path_1.default.join(__dirname, '../screenshots')));
// Routes
app.use('/api/scan', scan_1.scanRoutes);
app.use('/api/report', report_1.reportRoutes);
app.use('/api/lead', lead_1.leadRoutes);
app.use('/api/pdf', pdf_1.pdfRoutes);
// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'ok', timestamp: new Date().toISOString() });
});
app.listen(PORT, () => {
    console.log(`🚀 API server running on port ${PORT}`);
    console.log(`📊 Health check: http://localhost:${PORT}/health`);
});
