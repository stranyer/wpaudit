"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.logger = void 0;
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
class Logger {
    constructor() {
        this.logFile = path_1.default.join(process.cwd(), 'debug.log');
    }
    formatMessage(level, message, data) {
        const timestamp = new Date().toISOString();
        const dataStr = data ? `\n${JSON.stringify(data, null, 2)}` : '';
        return `[${timestamp}] [${level}] ${message}${dataStr}\n`;
    }
    writeToFile(message) {
        try {
            fs_1.default.appendFileSync(this.logFile, message);
        }
        catch (error) {
            console.error('Error writing to log file:', error);
        }
    }
    info(message, data) {
        const formattedMessage = this.formatMessage('INFO', message, data);
        console.log(formattedMessage);
        this.writeToFile(formattedMessage);
    }
    error(message, error) {
        const errorData = error instanceof Error ? {
            message: error.message,
            stack: error.stack,
            ...error
        } : error;
        const formattedMessage = this.formatMessage('ERROR', message, errorData);
        console.error(formattedMessage);
        this.writeToFile(formattedMessage);
    }
    warn(message, data) {
        const formattedMessage = this.formatMessage('WARN', message, data);
        console.warn(formattedMessage);
        this.writeToFile(formattedMessage);
    }
    debug(message, data) {
        const formattedMessage = this.formatMessage('DEBUG', message, data);
        console.log(formattedMessage);
        this.writeToFile(formattedMessage);
    }
    clear() {
        try {
            fs_1.default.writeFileSync(this.logFile, '');
            console.log('Log file cleared');
        }
        catch (error) {
            console.error('Error clearing log file:', error);
        }
    }
}
exports.logger = new Logger();
