import winston from 'winston';

const logLevel = process.env.LOG_LEVEL || 'info';
const nodeEnv = process.env.NODE_ENV || 'development';

// Custom format for structured logging
const logFormat = winston.format.combine(
  winston.format.timestamp(),
  winston.format.errors({ stack: true }),
  winston.format.json(),
  winston.format.printf(({ timestamp, level, message, service, ...meta }) => {
    return JSON.stringify({
      timestamp,
      level,
      service,
      message,
      ...meta
    });
  })
);

// Console format for development
const consoleFormat = winston.format.combine(
  winston.format.colorize(),
  winston.format.timestamp({ format: 'HH:mm:ss' }),
  winston.format.printf(({ timestamp, level, message, service, ...meta }) => {
    const metaStr = Object.keys(meta).length ? JSON.stringify(meta, null, 2) : '';
    return `${timestamp} [${service}] ${level}: ${message} ${metaStr}`;
  })
);

export function createLogger(service: string): winston.Logger {
  const transports: winston.transport[] = [];

  // Always add console transport
  transports.push(
    new winston.transports.Console({
      format: nodeEnv === 'production' ? logFormat : consoleFormat,
      level: logLevel
    })
  );

  // Add file transport in production
  if (nodeEnv === 'production') {
    transports.push(
      new winston.transports.File({
        filename: '/app/logs/error.log',
        level: 'error',
        format: logFormat,
        maxsize: 10 * 1024 * 1024, // 10MB
        maxFiles: 5
      }),
      new winston.transports.File({
        filename: '/app/logs/combined.log',
        format: logFormat,
        maxsize: 10 * 1024 * 1024, // 10MB
        maxFiles: 10
      })
    );
  }

  return winston.createLogger({
    level: logLevel,
    format: logFormat,
    defaultMeta: { service },
    transports,
    // Don't exit on handled exceptions
    exitOnError: false
  });
}