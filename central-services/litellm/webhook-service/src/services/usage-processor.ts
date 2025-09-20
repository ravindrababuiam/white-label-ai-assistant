import Bull, { Queue, Job } from 'bull';
import Redis from 'ioredis';
import { DatabaseService, UsageRecord } from './database';
import { LagoWebhookService } from './lago-webhook';
import { createLogger } from '../utils/logger';

const logger = createLogger('usage-processor');

export interface UsageJobData {
  requestId: string;
  retryCount?: number;
}

export class UsageProcessor {
  private static instance: UsageProcessor;
  private redis: Redis;
  private usageQueue: Queue<UsageJobData>;
  private dbService: DatabaseService;
  private lagoService: LagoWebhookService;

  private constructor() {
    this.dbService = DatabaseService.getInstance();
    this.lagoService = LagoWebhookService.getInstance();
  }

  static getInstance(): UsageProcessor {
    if (!UsageProcessor.instance) {
      UsageProcessor.instance = new UsageProcessor();
    }
    return UsageProcessor.instance;
  }

  async initialize(): Promise<void> {
    // Initialize Redis connection
    this.redis = new Redis({
      host: process.env.REDIS_HOST || 'localhost',
      port: parseInt(process.env.REDIS_PORT || '6379'),
      retryDelayOnFailover: 100,
      enableReadyCheck: false,
      maxRetriesPerRequest: null,
    });

    this.redis.on('error', (error) => {
      logger.error('Redis connection error', { error });
    });

    this.redis.on('connect', () => {
      logger.info('Redis connected');
    });

    // Initialize Bull queue
    this.usageQueue = new Bull<UsageJobData>('usage-processing', {
      redis: {
        host: process.env.REDIS_HOST || 'localhost',
        port: parseInt(process.env.REDIS_PORT || '6379'),
      },
      defaultJobOptions: {
        removeOnComplete: 100, // Keep last 100 completed jobs
        removeOnFail: 50,      // Keep last 50 failed jobs
        attempts: 3,           // Retry failed jobs 3 times
        backoff: {
          type: 'exponential',
          delay: 2000,         // Start with 2 second delay
        },
      },
    });

    // Setup job processing
    this.usageQueue.process('process-usage', 10, this.processUsageJob.bind(this));

    // Setup event handlers
    this.usageQueue.on('completed', (job: Job<UsageJobData>) => {
      logger.info('Usage job completed', {
        jobId: job.id,
        requestId: job.data.requestId,
        duration: Date.now() - job.timestamp
      });
    });

    this.usageQueue.on('failed', (job: Job<UsageJobData>, error: Error) => {
      logger.error('Usage job failed', {
        jobId: job.id,
        requestId: job.data.requestId,
        error: error.message,
        attempts: job.attemptsMade,
        maxAttempts: job.opts.attempts
      });
    });

    this.usageQueue.on('stalled', (job: Job<UsageJobData>) => {
      logger.warn('Usage job stalled', {
        jobId: job.id,
        requestId: job.data.requestId
      });
    });

    // Setup PostgreSQL LISTEN for real-time notifications
    await this.setupDatabaseListener();

    // Create webhook logs table
    await this.dbService.createWebhookLogTable();

    logger.info('Usage processor initialized');
  }

  private async setupDatabaseListener(): Promise<void> {
    try {
      const client = await this.dbService.getClient();
      
      await client.query('LISTEN usage_event');
      
      client.on('notification', async (msg) => {
        if (msg.channel === 'usage_event' && msg.payload) {
          logger.debug('Received usage event notification', { requestId: msg.payload });
          await this.queueUsageProcessing(msg.payload);
        }
      });

      logger.info('Database listener setup complete');
    } catch (error) {
      logger.error('Failed to setup database listener', { error });
      // Don't throw - we can still process via polling
    }
  }

  async queueUsageProcessing(requestId: string, priority: number = 0): Promise<void> {
    try {
      const job = await this.usageQueue.add(
        'process-usage',
        { requestId },
        {
          priority,
          delay: 1000, // Small delay to ensure database transaction is committed
        }
      );

      logger.debug('Usage processing job queued', {
        jobId: job.id,
        requestId,
        priority
      });
    } catch (error) {
      logger.error('Failed to queue usage processing', { requestId, error });
    }
  }

  private async processUsageJob(job: Job<UsageJobData>): Promise<void> {
    const { requestId } = job.data;
    
    logger.debug('Processing usage job', {
      jobId: job.id,
      requestId,
      attempt: job.attemptsMade + 1
    });

    try {
      // Get usage record from database
      const usageRecord = await this.dbService.getUsageRecord(requestId);
      
      if (!usageRecord) {
        logger.warn('Usage record not found', { requestId });
        return;
      }

      // Send to Lago webhook
      const success = await this.lagoService.sendUsageEvent(usageRecord);
      
      // Log webhook attempt
      await this.dbService.markWebhookSent(
        requestId,
        process.env.LAGO_WEBHOOK_URL || 'unknown',
        success
      );

      if (!success) {
        throw new Error('Failed to send usage event to Lago');
      }

      logger.info('Usage event processed successfully', { requestId });
    } catch (error) {
      logger.error('Failed to process usage job', {
        jobId: job.id,
        requestId,
        error: error.message,
        attempt: job.attemptsMade + 1
      });
      throw error; // Re-throw to trigger retry
    }
  }

  async processBacklog(limit: number = 100): Promise<void> {
    logger.info('Processing usage backlog', { limit });

    try {
      // Get unprocessed usage records from the last 24 hours
      const query = `
        SELECT DISTINCT l."request_id"
        FROM "LiteLLM_SpendLogs" l
        LEFT JOIN webhook_logs w ON l."request_id" = w.request_id 
          AND w.webhook_url = $1 
          AND w.success = true
        WHERE l."startTime" > NOW() - INTERVAL '24 hours'
          AND w.request_id IS NULL
        ORDER BY l."startTime" DESC
        LIMIT $2
      `;

      const result = await this.dbService.query(query, [
        process.env.LAGO_WEBHOOK_URL || 'unknown',
        limit
      ]);

      const requestIds = result.rows.map((row: any) => row.request_id);
      
      logger.info('Found unprocessed usage records', { count: requestIds.length });

      // Queue all unprocessed records
      for (const requestId of requestIds) {
        await this.queueUsageProcessing(requestId, -1); // Lower priority for backlog
      }

    } catch (error) {
      logger.error('Failed to process backlog', { error });
    }
  }

  async getQueueStats(): Promise<any> {
    try {
      const waiting = await this.usageQueue.getWaiting();
      const active = await this.usageQueue.getActive();
      const completed = await this.usageQueue.getCompleted();
      const failed = await this.usageQueue.getFailed();

      return {
        waiting: waiting.length,
        active: active.length,
        completed: completed.length,
        failed: failed.length,
        total: waiting.length + active.length + completed.length + failed.length
      };
    } catch (error) {
      logger.error('Failed to get queue stats', { error });
      return null;
    }
  }

  async shutdown(): Promise<void> {
    logger.info('Shutting down usage processor');

    try {
      // Close queue
      if (this.usageQueue) {
        await this.usageQueue.close();
      }

      // Close Redis connection
      if (this.redis) {
        this.redis.disconnect();
      }

      logger.info('Usage processor shutdown complete');
    } catch (error) {
      logger.error('Error during usage processor shutdown', { error });
    }
  }
}