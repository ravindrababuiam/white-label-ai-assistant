import { Router, Request, Response } from 'express';
import { DatabaseService } from '../services/database';
import { LagoWebhookService } from '../services/lago-webhook';
import { UsageProcessor } from '../services/usage-processor';
import { createLogger } from '../utils/logger';

const logger = createLogger('health-routes');
const router = Router();

// GET /health - Basic health check
router.get('/', async (req: Request, res: Response) => {
  const health = {
    status: 'healthy',
    timestamp: new Date().toISOString(),
    version: process.env.npm_package_version || '1.0.0',
    uptime: process.uptime(),
    memory: process.memoryUsage(),
    services: {
      database: 'unknown',
      lago: 'unknown',
      redis: 'unknown'
    }
  };

  let statusCode = 200;

  try {
    // Check database connection
    const dbService = DatabaseService.getInstance();
    await dbService.query('SELECT 1');
    health.services.database = 'healthy';
  } catch (error) {
    health.services.database = 'unhealthy';
    health.status = 'degraded';
    statusCode = 503;
    logger.error('Database health check failed', { error: error.message });
  }

  try {
    // Check Lago webhook endpoint
    const lagoService = LagoWebhookService.getInstance();
    const lagoHealthy = await lagoService.validateWebhookEndpoint();
    health.services.lago = lagoHealthy ? 'healthy' : 'unhealthy';
    
    if (!lagoHealthy) {
      health.status = 'degraded';
      if (statusCode === 200) statusCode = 503;
    }
  } catch (error) {
    health.services.lago = 'unhealthy';
    health.status = 'degraded';
    if (statusCode === 200) statusCode = 503;
    logger.error('Lago health check failed', { error: error.message });
  }

  try {
    // Check Redis/Queue status
    const usageProcessor = UsageProcessor.getInstance();
    const queueStats = await usageProcessor.getQueueStats();
    
    if (queueStats) {
      health.services.redis = 'healthy';
      (health as any).queue_stats = queueStats;
    } else {
      health.services.redis = 'unhealthy';
      health.status = 'degraded';
      if (statusCode === 200) statusCode = 503;
    }
  } catch (error) {
    health.services.redis = 'unhealthy';
    health.status = 'degraded';
    if (statusCode === 200) statusCode = 503;
    logger.error('Redis health check failed', { error: error.message });
  }

  res.status(statusCode).json(health);
});

// GET /health/ready - Readiness probe
router.get('/ready', async (req: Request, res: Response) => {
  try {
    // Check if all critical services are available
    const dbService = DatabaseService.getInstance();
    await dbService.query('SELECT 1');

    const usageProcessor = UsageProcessor.getInstance();
    const queueStats = await usageProcessor.getQueueStats();

    if (!queueStats) {
      throw new Error('Queue not available');
    }

    res.status(200).json({
      status: 'ready',
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    logger.error('Readiness check failed', { error: error.message });
    
    res.status(503).json({
      status: 'not ready',
      error: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

// GET /health/live - Liveness probe
router.get('/live', (req: Request, res: Response) => {
  // Simple liveness check - just verify the process is running
  res.status(200).json({
    status: 'alive',
    timestamp: new Date().toISOString(),
    pid: process.pid,
    uptime: process.uptime()
  });
});

// GET /health/metrics - Basic metrics for monitoring
router.get('/metrics', async (req: Request, res: Response) => {
  try {
    const dbService = DatabaseService.getInstance();
    const usageProcessor = UsageProcessor.getInstance();

    // Get queue statistics
    const queueStats = await usageProcessor.getQueueStats();

    // Get recent processing metrics
    const metricsQuery = `
      SELECT 
        COUNT(*) as total_events_24h,
        COUNT(CASE WHEN w.success = true THEN 1 END) as successful_webhooks_24h,
        COUNT(CASE WHEN w.success = false THEN 1 END) as failed_webhooks_24h,
        AVG(EXTRACT(EPOCH FROM (w.sent_at - l."startTime"))) as avg_processing_delay_seconds
      FROM "LiteLLM_SpendLogs" l
      LEFT JOIN webhook_logs w ON l."request_id" = w.request_id
      WHERE l."startTime" > NOW() - INTERVAL '24 hours'
    `;

    const metricsResult = await dbService.query(metricsQuery);
    const metrics = metricsResult.rows[0];

    // Calculate success rate
    const totalProcessed = parseInt(metrics.successful_webhooks_24h) + parseInt(metrics.failed_webhooks_24h);
    const successRate = totalProcessed > 0 ? 
      (parseInt(metrics.successful_webhooks_24h) / totalProcessed * 100).toFixed(2) : 
      '0.00';

    res.json({
      timestamp: new Date().toISOString(),
      process: {
        uptime_seconds: process.uptime(),
        memory_usage: process.memoryUsage(),
        cpu_usage: process.cpuUsage()
      },
      queue: queueStats,
      processing: {
        total_events_24h: parseInt(metrics.total_events_24h),
        successful_webhooks_24h: parseInt(metrics.successful_webhooks_24h),
        failed_webhooks_24h: parseInt(metrics.failed_webhooks_24h),
        success_rate_percent: parseFloat(successRate),
        avg_processing_delay_seconds: parseFloat(metrics.avg_processing_delay_seconds) || 0
      }
    });

  } catch (error) {
    logger.error('Failed to get metrics', { error: error.message });
    
    res.status(500).json({
      error: 'Failed to get metrics',
      timestamp: new Date().toISOString()
    });
  }
});

export { router as healthRoutes };