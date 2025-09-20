import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import dotenv from 'dotenv';
import { createLogger } from './utils/logger';
import { DatabaseService } from './services/database';
import { LagoWebhookService } from './services/lago-webhook';
import { UsageProcessor } from './services/usage-processor';
import { webhookRoutes } from './routes/webhook';
import { healthRoutes } from './routes/health';

dotenv.config();

const logger = createLogger('main');
const app = express();
const port = process.env.PORT || 3001;

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// Request logging middleware
app.use((req, res, next) => {
  logger.info(`${req.method} ${req.path}`, {
    ip: req.ip,
    userAgent: req.get('User-Agent'),
    requestId: req.headers['x-request-id']
  });
  next();
});

async function initializeServices() {
  try {
    // Initialize database connection
    const dbService = DatabaseService.getInstance();
    await dbService.connect();
    logger.info('Database connected successfully');

    // Initialize Lago webhook service
    const lagoService = LagoWebhookService.getInstance();
    await lagoService.initialize();
    logger.info('Lago webhook service initialized');

    // Initialize usage processor
    const usageProcessor = UsageProcessor.getInstance();
    await usageProcessor.initialize();
    logger.info('Usage processor initialized');

    return { dbService, lagoService, usageProcessor };
  } catch (error) {
    logger.error('Failed to initialize services', { error });
    throw error;
  }
}

async function startServer() {
  try {
    // Initialize services
    await initializeServices();

    // Setup routes
    app.use('/health', healthRoutes);
    app.use('/webhooks', webhookRoutes);

    // Error handling middleware
    app.use((error: Error, req: express.Request, res: express.Response, next: express.NextFunction) => {
      logger.error('Unhandled error', { 
        error: error.message, 
        stack: error.stack,
        path: req.path,
        method: req.method
      });
      
      res.status(500).json({
        error: 'Internal server error',
        requestId: req.headers['x-request-id']
      });
    });

    // 404 handler
    app.use('*', (req, res) => {
      res.status(404).json({
        error: 'Not found',
        path: req.originalUrl
      });
    });

    // Start server
    app.listen(port, () => {
      logger.info(`Webhook service started on port ${port}`);
    });

    // Graceful shutdown
    process.on('SIGTERM', async () => {
      logger.info('Received SIGTERM, shutting down gracefully');
      
      const dbService = DatabaseService.getInstance();
      await dbService.disconnect();
      
      const usageProcessor = UsageProcessor.getInstance();
      await usageProcessor.shutdown();
      
      process.exit(0);
    });

    process.on('SIGINT', async () => {
      logger.info('Received SIGINT, shutting down gracefully');
      
      const dbService = DatabaseService.getInstance();
      await dbService.disconnect();
      
      const usageProcessor = UsageProcessor.getInstance();
      await usageProcessor.shutdown();
      
      process.exit(0);
    });

  } catch (error) {
    logger.error('Failed to start server', { error });
    process.exit(1);
  }
}

startServer();