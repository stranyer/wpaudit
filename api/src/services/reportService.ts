interface Report {
  id: string
  publicId: string
  url: string
  createdAt: string
  data: any
}

class ReportService {
  private reports: Map<string, Report> = new Map()
  private publicReports: Map<string, string> = new Map() // publicId -> reportId

  async getReport(reportId: string): Promise<Report | null> {
    return this.reports.get(reportId) || null
  }

  async getPublicReport(publicId: string): Promise<Report | null> {
    const reportId = this.publicReports.get(publicId)
    if (!reportId) return null
    
    return this.reports.get(reportId) || null
  }

  async createReport(url: string, data: any): Promise<Report> {
    const reportId = this.generateId()
    const publicId = this.generatePublicId()
    
    const report: Report = {
      id: reportId,
      publicId,
      url,
      createdAt: new Date().toISOString(),
      data
    }
    
    this.reports.set(reportId, report)
    this.publicReports.set(publicId, reportId)
    
    return report
  }

  private generateId(): string {
    return Math.random().toString(36).substr(2, 9)
  }

  private generatePublicId(): string {
    return Math.random().toString(36).substr(2, 12)
  }
}

export const reportService = new ReportService()