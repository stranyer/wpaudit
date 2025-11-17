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
// Configure CORS to allow requests from WordPress and local development
const allowedOrigins = [
    'http://localhost:3000',
    'http://wpaudit.test:3000',
    'http://wpaudit.test',
    'https://justspeedit.com',
    'http://justspeedit.com',
    'https://www.justspeedit.com',
    'http://www.justspeedit.com'
];
app.use((0, cors_1.default)({
    origin: function (origin, callback) {
        // Allow requests with no origin (like mobile apps or curl)
        if (!origin)
            return callback(null, true);
        if (allowedOrigins.indexOf(origin) !== -1) {
            callback(null, true);
        }
        else {
            // For development, allow all origins
            if (process.env.NODE_ENV !== 'production') {
                callback(null, true);
            }
            else {
                callback(new Error('Not allowed by CORS'));
            }
        }
    },
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
