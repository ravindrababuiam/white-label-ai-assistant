import { Router, Request, Response } from 'express';
import Joi from 'joi';
import { UsageProcessor } from '../services/usage-processor';
import { DatabaseService } from '../services/database';
import { LagoWebhookService } from '../services/lago-webhook';
import { createLogger } from '../utils/logger';

const logger = createLogger('webhook-routes');
const router = Router();

// Validation schemas
const usageEventSchema = Joi.object({
  request_id: Joi.string().required(),
  model: Joi.string().required(),
  end_user: Joi.string().required(),
  prompt_tokens: Joi.number().integer().min(0).default(0),
  completion_tokens: Joi.number().integer().min(0).default(0),
  total_tokens: Joi.number().integer().min(0).default(0),
  spend: Joi.number().min(0).default(0),
  startTime: Joi.date().iso().required(),
  endTime: Joi.date().iso().optional(),
  custom_llm_provider: Joi.string().optional(),
  api_key: Joi.string().optional(),
  user: Joi.string().optional(),
  team_id: Joi.string().optional(),
  request_tags: Joi.any().optional()
});

const batchUsageSchema = Joi.object({
  events: Joi.array().items(usageEventSchema).min(1).max(100).required()
});

// Middleware for request validation
function validateRequest(schema: Joi.ObjectSchema) {
  return (req: Request, res: Response, next: Function) => {
    const { error, value } = schema.validate(req.body);
    
    if (error) {
      logger.warn('Request validation failed', {
        path: req.path,
        error: error.details[0].message,
        body: req.body
      });
      
      return res.status(400).json({
        error: 'Validation failed',
        details: error.details[0].message
      });
    }
    
    req.body = value;
    next();
  };
}

// POST /webhooks/usage - Single usage event
router.post('/usage', validateRequest(usageEventSchema), async (req: Request, res: Response) => {
  try {
    const usageProcessor = UsageProcessor.getInstance();
    
    logger.info('Received usage event', {
      requestId: req.body.request_id,
      model: req.body.model,
      endUser: req.body.end_user,
      totalTokens: req.body.total_tokens
    });

    // Queue for processing
    await usageProcessor.queueUsageProcessing(req.body.request_id, 1);

    res.status(202).json({
      message: 'Usage event queued for processing',
      request_id: req.body.request_id
    });

  } catch (error) {
    logger.error('Failed to process usage event', {
      requestId: req.body.request_id,
      error: error.message
    });

    res.status(500).json({
      error: 'Failed to process usage event',
      request_id: req.body.request_id
    });
  }
});

// POST /webhooks/usage/batch - Batch usage events
router.post('/usage/batch', validateRequest(batchUsageSchema), async (req: Request, res: Response) => {
  try {
    const usageProcessor = UsageProcessor.getInstance();
    const events = req.body.events;

    logger.info('Received batch usage events', { count: events.length });

    // Queue all events for processing
    const promises = events.map((event: any) => 
      usageProcessor.queueUsageProcessing(event.request_id, 1)
    );

    await Promise.all(promises);

    res.status(202).json({
      message: 'Batch usage events queued for processing',
      count: events.length,
      request_ids: events.map((e: any) => e.request_id)
    });

  } catch (error) {
    logger.error('Failed to process batch usage events', {
      count: req.body.events?.length,
      error: error.message
    });

    res.status(500).json({
      error: 'Failed to process batch usage events'
    });
  }
});

// POST /webhooks/reprocess - Reprocess failed events
router.post('/reprocess', async (req: Request, res: Response) => {
  try {
    const { request_ids, hours = 24 } = req.body;
    const usageProcessor = UsageProcessor.getInstance();

    if (request_ids && Array.isArray(request_ids)) {
      // Reprocess specific request IDs
      logger.info('Reprocessing specific usage events', { 
        count: request_ids.length,
        requestIds: request_ids 
      });

      const promises = request_ids.map((requestId: string) => 
        usageProcessor.queueUsageProcessing(requestId, 2) // Higher priority
      );

      await Promise.all(promises);

      res.json({
        message: 'Usage events queued for reprocessing',
        count: request_ids.length
      });
    } else {
      // Reprocess backlog
      logger.info('Reprocessing usage backlog', { hours });
      
      await usageProcessor.processBacklog(1000);

      res.json({
        message: 'Backlog processing initiated',
        hours
      });
    }

  } catch (error) {
    logger.error('Failed to reprocess usage events', { error: error.message });

    res.status(500).json({
      error: 'Failed to reprocess usage events'
    });
  }
});

// GET /webhooks/stats - Get processing statistics
router.get('/stats', async (req: Request, res: Response) => {
  try {
    const usageProcessor = UsageProcessor.getInstance();
    const dbService = DatabaseService.getInstance();

    const queueStats = await usageProcessor.getQueueStats();
    
    // Get recent processing stats from database
    const recentStatsQuery = `
      SELECT 
        COUNT(*) as total_events,
        COUNT(CASE WHEN w.success = true THEN 1 END) as successful_webhooks,
        COUNT(CASE WHEN w.success = false THEN 1 END) as failed_webhooks,
        COUNT(CASE WHEN w.request_id IS NULL THEN 1 END) as pending_webhooks
      FROM "LiteLLM_SpendLogs" l
      LEFT JOIN webhook_logs w ON l."request_id" = w.request_id 
        AND w.webhook_url = $1
      WHERE l."startTime" > NOW() - INTERVAL '1 hour'
    `;

    const recentStats = await dbService.query(recentStatsQuery, [
      process.env.LAGO_WEBHOOK_URL || 'unknown'
    ]);

    res.json({
      queue: queueStats,
      recent_hour: recentStats.rows[0],
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    logger.error('Failed to get webhook stats', { error: error.message });

    res.status(500).json({
      error: 'Failed to get webhook stats'
    });
  }
});

// GET /webhooks/validate - Validate Lago connection
router.get('/validate', async (req: Request, res: Response) => {
  try {
    const lagoService = LagoWebhookService.getInstance();
    const isValid = await lagoService.validateWebhookEndpoint();

    res.json({
      valid: isValid,
      webhook_url: process.env.LAGO_WEBHOOK_URL,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    logger.error('Failed to validate webhook endpoint', { error: error.message });

    res.status(500).json({
      error: 'Failed to validate webhook endpoint',
      valid: false
    });
  }
});

export { router as webhookRoutes };