"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.reportService = void 0;
class ReportService {
    constructor() {
        this.reports = new Map();
        this.publicReports = new Map(); // publicId -> reportId
    }
    async getReport(reportId) {
        return this.reports.get(reportId) || null;
    }
    async getPublicReport(publicId) {
        const reportId = this.publicReports.get(publicId);
        if (!reportId)
            return null;
        return this.reports.get(reportId) || null;
    }
    async createReport(url, data) {
        const reportId = this.generateId();
        const publicId = this.generatePublicId();
        const report = {
            id: reportId,
            publicId,
            url,
            createdAt: new Date().toISOString(),
            data
        };
        this.reports.set(reportId, report);
        this.publicReports.set(publicId, reportId);
        return report;
    }
    generateId() {
        return Math.random().toString(36).substr(2, 9);
    }
    generatePublicId() {
        return Math.random().toString(36).substr(2, 12);
    }
}
exports.reportService = new ReportService();
