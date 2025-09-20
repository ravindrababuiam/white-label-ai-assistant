import { Router, Request, Response } from 'express';
import { DatabaseService } from '../services/database';
import { LagoApiService } from '../services/lago-api';
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
      lago_api: 'unknown'
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
    // Check Lago API connection
    const lagoService = LagoApiService.getInstance();
    await lagoService.getCurrentOrganization();
    health.services.lago_api = 'healthy';
  } catch (error) {
    health.services.lago_api = 'unhealthy';
    health.status = 'degraded';
    if (statusCode === 200) statusCode = 503;
    logger.error('Lago API health check failed', { error: error.message });
  }

  res.status(statusCode).json(health);
});

// GET /health/ready - Readiness probe
router.get('/ready', async (req: Request, res: Response) => {
  try {
    // Check if all critical services are available
    const dbService = DatabaseService.getInstance();
    await dbService.query('SELECT 1');

    const lagoService = LagoApiService.getInstance();
    await lagoService.getCurrentOrganization();

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

    // Get recent processing metrics
    const metricsQuery = `
      SELECT 
        COUNT(*) as total_events_24h,
        COUNT(CASE WHEN processed_at IS NOT NULL THEN 1 END) as processed_events_24h,
        COUNT(CASE WHEN processed_at IS NULL THEN 1 END) as pending_events_24h,
        SUM(total_tokens) as total_tokens_24h,
        SUM(cost_usd) as total_cost_usd_24h,
        AVG(EXTRACT(EPOCH FROM (processed_at - timestamp))) as avg_processing_delay_seconds
      FROM litellm_usage_events
      WHERE timestamp > NOW() - INTERVAL '24 hours'
    `;

    const metricsResult = await dbService.query(metricsQuery);
    const metrics = metricsResult.rows[0];

    // Get webhook delivery stats
    const webhookStats = await dbService.getWebhookDeliveryStats(24);

    // Calculate processing rate
    const totalProcessed = parseInt(metrics.processed_events_24h) || 0;
    const totalEvents = parseInt(metrics.total_events_24h) || 0;
    const processingRate = totalEvents > 0 ? (totalProcessed / totalEvents * 100).toFixed(2) : '0.00';

    res.json({
      timestamp: new Date().toISOString(),
      process: {
        uptime_seconds: process.uptime(),
        memory_usage: process.memoryUsage(),
        cpu_usage: process.cpuUsage()
      },
      events: {
        total_events_24h: totalEvents,
        processed_events_24h: totalProcessed,
        pending_events_24h: parseInt(metrics.pending_events_24h) || 0,
        processing_rate_percent: parseFloat(processingRate),
        avg_processing_delay_seconds: parseFloat(metrics.avg_processing_delay_seconds) || 0
      },
      usage: {
        total_tokens_24h: parseInt(metrics.total_tokens_24h) || 0,
        total_cost_usd_24h: parseFloat(metrics.total_cost_usd_24h) || 0
      },
      webhooks: webhookStats.reduce((acc: any, stat: any) => {
        acc.total_attempts += stat.total_attempts || 0;
        acc.successful_deliveries += stat.successful_deliveries || 0;
        acc.failed_deliveries += stat.failed_deliveries || 0;
        return acc;
      }, { total_attempts: 0, successful_deliveries: 0, failed_deliveries: 0 })
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