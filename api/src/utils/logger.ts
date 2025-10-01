import fs from 'fs'
import path from 'path'

class Logger {
  private logFile: string
  
  constructor() {
    this.logFile = path.join(process.cwd(), 'debug.log')
  }
  
  private formatMessage(level: string, message: string, data?: any): string {
    const timestamp = new Date().toISOString()
    const dataStr = data ? `\n${JSON.stringify(data, null, 2)}` : ''
    return `[${timestamp}] [${level}] ${message}${dataStr}\n`
  }
  
  private writeToFile(message: string) {
    try {
      fs.appendFileSync(this.logFile, message)
    } catch (error) {
      console.error('Error writing to log file:', error)
    }
  }
  
  info(message: string, data?: any) {
    const formattedMessage = this.formatMessage('INFO', message, data)
    console.log(formattedMessage)
    this.writeToFile(formattedMessage)
  }
  
  error(message: string, error?: any) {
    const errorData = error instanceof Error ? {
      message: error.message,
      stack: error.stack,
      ...error
    } : error
    
    const formattedMessage = this.formatMessage('ERROR', message, errorData)
    console.error(formattedMessage)
    this.writeToFile(formattedMessage)
  }
  
  warn(message: string, data?: any) {
    const formattedMessage = this.formatMessage('WARN', message, data)
    console.warn(formattedMessage)
    this.writeToFile(formattedMessage)
  }
  
  debug(message: string, data?: any) {
    const formattedMessage = this.formatMessage('DEBUG', message, data)
    console.log(formattedMessage)
    this.writeToFile(formattedMessage)
  }
  
  clear() {
    try {
      fs.writeFileSync(this.logFile, '')
      console.log('Log file cleared')
    } catch (error) {
      console.error('Error clearing log file:', error)
    }
  }
}

export const logger = new Logger()
