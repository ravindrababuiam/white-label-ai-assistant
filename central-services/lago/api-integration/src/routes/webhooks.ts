import { Router, Request, Response } from 'express';
import Joi from 'joi';
import { LagoApiService } from '../services/lago-api';
import { DatabaseService } from '../services/database';
import { createLogger } from '../utils/logger';

const logger = createLogger('webhooks-routes');
const router = Router();

// Validation schemas
const usageEventSchema = Joi.object({
  event_type: Joi.string().valid('usage').required(),
  timestamp: Joi.number().integer().required(),
  customer_id: Joi.string().required(),
  model: Joi.string().required(),
  provider: Joi.string().required(),
  tokens_input: Joi.number().integer().min(0).required(),
  tokens_output: Joi.number().integer().min(0).required(),
  total_tokens: Joi.number().integer().min(0).required(),
  cost_usd: Joi.number().min(0).required(),
  request_id: Joi.string().required(),
  api_key_hash: Joi.string().required(),
  metadata: Joi.object({
    user_id: Joi.string().optional(),
    team_id: Joi.string().optional(),
    request_tags: Joi.any().optional()
  }).optional()
});

const batchUsageEventsSchema = Joi.object({
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

// POST /webhooks/litellm - Receive usage events from LiteLLM
router.post('/litellm', validateRequest(usageEventSchema), async (req: Request, res: Response) => {
  try {
    const lagoService = LagoApiService.getInstance();
    const dbService = DatabaseService.getInstance();
    const event = req.body;

    logger.info('Received usage event from LiteLLM', {
      requestId: event.request_id,
      customerId: event.customer_id,
      model: event.model,
      totalTokens: event.total_tokens,
      cost: event.cost_usd
    });

    // Store event in local database
    const usageEvent = {
      request_id: event.request_id,
      customer_external_id: event.customer_id,
      model: event.model,
      provider: event.provider,
      tokens_input: event.tokens_input,
      tokens_output: event.tokens_output,
      total_tokens: event.total_tokens,
      cost_usd: event.cost_usd,
      timestamp: new Date(event.timestamp * 1000)
    };

    const eventId = await dbService.storeUsageEvent(usageEvent);

    // Send event to Lago
    const lagoEvent = {
      transaction_id: event.request_id,
      external_customer_id: event.customer_id,
      code: 'ai_usage',
      timestamp: event.timestamp,
      properties: {
        model: event.model,
        provider: event.provider,
        tokens_input: event.tokens_input,
        tokens_output: event.tokens_output,
        total_tokens: event.total_tokens,
        cost_usd: event.cost_usd,
        api_key_hash: event.api_key_hash,
        user_id: event.metadata?.user_id,
        team_id: event.metadata?.team_id,
        request_tags: event.metadata?.request_tags
      }
    };

    try {
      await lagoService.sendEvent(lagoEvent);
      await dbService.markEventProcessed(event.request_id, event.request_id);
      
      logger.info('Usage event processed successfully', {
        requestId: event.request_id,
        eventId
      });
    } catch (lagoError) {
      logger.error('Failed to send event to Lago', {
        requestId: event.request_id,
        error: lagoError.message
      });
      
      // Event is stored locally, can be retried later
    }

    res.status(200).json({
      message: 'Usage event received and processed',
      event_id: eventId,
      request_id: event.request_id
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

// POST /webhooks/litellm/batch - Receive batch usage events from LiteLLM
router.post('/litellm/batch', validateRequest(batchUsageEventsSchema), async (req: Request, res: Response) => {
  try {
    const lagoService = LagoApiService.getInstance();
    const dbService = DatabaseService.getInstance();
    const events = req.body.events;

    logger.info('Received batch usage events from LiteLLM', { count: events.length });

    const processedEvents = [];
    const failedEvents = [];

    // Process events in parallel with concurrency limit
    const concurrency = 5;
    const chunks = [];
    
    for (let i = 0; i < events.length; i += concurrency) {
      chunks.push(events.slice(i, i + concurrency));
    }

    for (const chunk of chunks) {
      const promises = chunk.map(async (event: any) => {
        try {
          // Store event in local database
          const usageEvent = {
            request_id: event.request_id,
            customer_external_id: event.customer_id,
            model: event.model,
            provider: event.provider,
            tokens_input: event.tokens_input,
            tokens_output: event.tokens_output,
            total_tokens: event.total_tokens,
            cost_usd: event.cost_usd,
            timestamp: new Date(event.timestamp * 1000)
          };

          const eventId = await dbService.storeUsageEvent(usageEvent);

          // Prepare Lago event
          const lagoEvent = {
            transaction_id: event.request_id,
            external_customer_id: event.customer_id,
            code: 'ai_usage',
            timestamp: event.timestamp,
            properties: {
              model: event.model,
              provider: event.provider,
              tokens_input: event.tokens_input,
              tokens_output: event.tokens_output,
              total_tokens: event.total_tokens,
              cost_usd: event.cost_usd,
              api_key_hash: event.api_key_hash,
              user_id: event.metadata?.user_id,
              team_id: event.metadata?.team_id,
              request_tags: event.metadata?.request_tags
            }
          };

          return { event, lagoEvent, eventId, success: true };
        } catch (error) {
          logger.error('Failed to process individual event', {
            requestId: event.request_id,
            error: error.message
          });
          return { event, error: error.message, success: false };
        }
      });

      const results = await Promise.all(promises);
      
      // Separate successful and failed events
      const successfulEvents = results.filter(r => r.success).map(r => r.lagoEvent);
      const currentFailedEvents = results.filter(r => !r.success);

      // Send successful events to Lago in batch
      if (successfulEvents.length > 0) {
        try {
          await lagoService.sendBatchEvents(successfulEvents);
          
          // Mark events as processed
          for (const result of results.filter(r => r.success)) {
            await dbService.markEventProcessed(result.event.request_id, result.event.request_id);
            processedEvents.push(result.event.request_id);
          }
        } catch (lagoError) {
          logger.error('Failed to send batch events to Lago', {
            count: successfulEvents.length,
            error: lagoError.message
          });
          
          // Events are stored locally, can be retried later
          failedEvents.push(...successfulEvents.map(e => e.transaction_id));
        }
      }

      failedEvents.push(...currentFailedEvents.map(e => e.event.request_id));
    }

    logger.info('Batch processing completed', {
      total: events.length,
      processed: processedEvents.length,
      failed: failedEvents.length
    });

    res.status(200).json({
      message: 'Batch usage events processed',
      total_events: events.length,
      processed_events: processedEvents.length,
      failed_events: failedEvents.length,
      processed_request_ids: processedEvents,
      failed_request_ids: failedEvents
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

// POST /webhooks/retry - Retry failed events
router.post('/retry', async (req: Request, res: Response) => {
  try {
    const lagoService = LagoApiService.getInstance();
    const dbService = DatabaseService.getInstance();
    const limit = parseInt(req.body.limit as string) || 100;

    logger.info('Retrying failed events', { limit });

    // Get unprocessed events
    const unprocessedEvents = await dbService.getUnprocessedEvents(limit);

    if (unprocessedEvents.length === 0) {
      return res.json({
        message: 'No unprocessed events found',
        processed_count: 0
      });
    }

    // Convert to Lago events and send
    const lagoEvents = unprocessedEvents.map(event => ({
      transaction_id: event.request_id,
      external_customer_id: event.customer_external_id,
      code: 'ai_usage',
      timestamp: Math.floor(event.timestamp.getTime() / 1000),
      properties: {
        model: event.model,
        provider: event.provider,
        tokens_input: event.tokens_input,
        tokens_output: event.tokens_output,
        total_tokens: event.total_tokens,
        cost_usd: event.cost_usd
      }
    }));

    let processedCount = 0;
    const chunkSize = 10;

    for (let i = 0; i < lagoEvents.length; i += chunkSize) {
      const chunk = lagoEvents.slice(i, i + chunkSize);
      
      try {
        await lagoService.sendBatchEvents(chunk);
        
        // Mark events as processed
        for (const event of chunk) {
          await dbService.markEventProcessed(event.transaction_id, event.transaction_id);
          processedCount++;
        }
      } catch (error) {
        logger.error('Failed to retry batch of events', {
          chunkSize: chunk.length,
          error: error.message
        });
      }
    }

    logger.info('Retry completed', {
      totalEvents: unprocessedEvents.length,
      processedCount
    });

    res.json({
      message: 'Event retry completed',
      total_events: unprocessedEvents.length,
      processed_count: processedCount,
      failed_count: unprocessedEvents.length - processedCount
    });

  } catch (error) {
    logger.error('Failed to retry events', { error: error.message });

    res.status(500).json({
      error: 'Failed to retry events'
    });
  }
});

// GET /webhooks/stats - Get webhook processing statistics
router.get('/stats', async (req: Request, res: Response) => {
  try {
    const dbService = DatabaseService.getInstance();
    const hours = parseInt(req.query.hours as string) || 24;

    // Get webhook delivery stats
    const deliveryStats = await dbService.getWebhookDeliveryStats(hours);

    // Get unprocessed events count
    const unprocessedEvents = await dbService.getUnprocessedEvents(1);
    const unprocessedQuery = `
      SELECT COUNT(*) as count FROM litellm_usage_events 
      WHERE processed_at IS NULL
    `;
    const unprocessedResult = await dbService.query(unprocessedQuery);
    const unprocessedCount = parseInt(unprocessedResult.rows[0].count);

    // Get recent events stats
    const recentStatsQuery = `
      SELECT 
        COUNT(*) as total_events,
        COUNT(CASE WHEN processed_at IS NOT NULL THEN 1 END) as processed_events,
        COUNT(CASE WHEN processed_at IS NULL THEN 1 END) as pending_events,
        SUM(total_tokens) as total_tokens,
        SUM(cost_usd) as total_cost_usd
      FROM litellm_usage_events
      WHERE timestamp > NOW() - INTERVAL '${hours} hours'
    `;
    const recentStatsResult = await dbService.query(recentStatsQuery);
    const recentStats = recentStatsResult.rows[0];

    const stats = {
      period: {
        hours,
        start_time: new Date(Date.now() - hours * 60 * 60 * 1000).toISOString(),
        end_time: new Date().toISOString()
      },
      events: {
        total: parseInt(recentStats.total_events),
        processed: parseInt(recentStats.processed_events),
        pending: parseInt(recentStats.pending_events),
        unprocessed_backlog: unprocessedCount
      },
      usage: {
        total_tokens: parseInt(recentStats.total_tokens) || 0,
        total_cost_usd: parseFloat(recentStats.total_cost_usd) || 0
      },
      webhook_deliveries: deliveryStats,
      timestamp: new Date().toISOString()
    };

    res.json(stats);

  } catch (error) {
    logger.error('Failed to get webhook stats', { error: error.message });

    res.status(500).json({
      error: 'Failed to get webhook stats'
    });
  }
});

export { router as webhookRoutes };