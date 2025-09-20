import { Pool, PoolClient } from 'pg';
import { createLogger } from '../utils/logger';

const logger = createLogger('database');

export interface UsageRecord {
  request_id: string;
  startTime: Date;
  endTime: Date;
  model: string;
  custom_llm_provider?: string;
  api_key: string;
  end_user: string;
  user?: string;
  team_id?: string;
  prompt_tokens: number;
  completion_tokens: number;
  total_tokens: number;
  spend: number;
  request_tags?: any;
}

export class DatabaseService {
  private static instance: DatabaseService;
  private pool: Pool | null = null;

  private constructor() {}

  static getInstance(): DatabaseService {
    if (!DatabaseService.instance) {
      DatabaseService.instance = new DatabaseService();
    }
    return DatabaseService.instance;
  }

  async connect(): Promise<void> {
    if (this.pool) {
      return;
    }

    const config = {
      host: process.env.DB_HOST || 'localhost',
      port: parseInt(process.env.DB_PORT || '5432'),
      database: process.env.DB_NAME || 'litellm',
      user: process.env.DB_USER || 'litellm',
      password: process.env.DB_PASSWORD,
      max: 20,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 2000,
    };

    this.pool = new Pool(config);

    // Test connection
    try {
      const client = await this.pool.connect();
      await client.query('SELECT NOW()');
      client.release();
      logger.info('Database connection established');
    } catch (error) {
      logger.error('Failed to connect to database', { error });
      throw error;
    }

    // Setup connection error handling
    this.pool.on('error', (err) => {
      logger.error('Unexpected error on idle client', { error: err });
    });
  }

  async disconnect(): Promise<void> {
    if (this.pool) {
      await this.pool.end();
      this.pool = null;
      logger.info('Database connection closed');
    }
  }

  async getClient(): Promise<PoolClient> {
    if (!this.pool) {
      throw new Error('Database not connected');
    }
    return this.pool.connect();
  }

  async query(text: string, params?: any[]): Promise<any> {
    if (!this.pool) {
      throw new Error('Database not connected');
    }
    
    const start = Date.now();
    try {
      const result = await this.pool.query(text, params);
      const duration = Date.now() - start;
      
      logger.debug('Query executed', {
        query: text,
        duration,
        rows: result.rowCount
      });
      
      return result;
    } catch (error) {
      logger.error('Query failed', {
        query: text,
        params,
        error
      });
      throw error;
    }
  }

  async getUsageRecord(requestId: string): Promise<UsageRecord | null> {
    const query = `
      SELECT 
        "request_id",
        "startTime",
        "endTime", 
        "model",
        "custom_llm_provider",
        "api_key",
        "end_user",
        "user",
        "team_id",
        "prompt_tokens",
        "completion_tokens", 
        "total_tokens",
        "spend",
        "request_tags"
      FROM "LiteLLM_SpendLogs"
      WHERE "request_id" = $1
    `;

    try {
      const result = await this.query(query, [requestId]);
      
      if (result.rows.length === 0) {
        return null;
      }

      const row = result.rows[0];
      return {
        request_id: row.request_id,
        startTime: row.startTime,
        endTime: row.endTime,
        model: row.model,
        custom_llm_provider: row.custom_llm_provider,
        api_key: row.api_key,
        end_user: row.end_user,
        user: row.user,
        team_id: row.team_id,
        prompt_tokens: row.prompt_tokens || 0,
        completion_tokens: row.completion_tokens || 0,
        total_tokens: row.total_tokens || 0,
        spend: parseFloat(row.spend) || 0,
        request_tags: row.request_tags
      };
    } catch (error) {
      logger.error('Failed to get usage record', { requestId, error });
      throw error;
    }
  }

  async getUsageByCustomer(
    customerId: string,
    startDate: Date,
    endDate: Date
  ): Promise<any> {
    const query = `
      SELECT * FROM get_usage_by_customer($1, $2, $3)
    `;

    try {
      const result = await this.query(query, [customerId, startDate, endDate]);
      return result.rows[0] || {
        total_requests: 0,
        total_tokens_input: 0,
        total_tokens_output: 0,
        total_cost: 0,
        model_breakdown: {}
      };
    } catch (error) {
      logger.error('Failed to get customer usage', { customerId, error });
      throw error;
    }
  }

  async markWebhookSent(requestId: string, webhookUrl: string, success: boolean): Promise<void> {
    const query = `
      INSERT INTO webhook_logs (request_id, webhook_url, sent_at, success, retry_count)
      VALUES ($1, $2, NOW(), $3, 0)
      ON CONFLICT (request_id, webhook_url) 
      DO UPDATE SET 
        sent_at = NOW(),
        success = $3,
        retry_count = webhook_logs.retry_count + 1
    `;

    try {
      await this.query(query, [requestId, webhookUrl, success]);
    } catch (error) {
      logger.error('Failed to mark webhook status', { requestId, webhookUrl, success, error });
      // Don't throw here as this is just logging
    }
  }

  async createWebhookLogTable(): Promise<void> {
    const query = `
      CREATE TABLE IF NOT EXISTS webhook_logs (
        id SERIAL PRIMARY KEY,
        request_id VARCHAR(255) NOT NULL,
        webhook_url VARCHAR(500) NOT NULL,
        sent_at TIMESTAMP DEFAULT NOW(),
        success BOOLEAN NOT NULL,
        retry_count INTEGER DEFAULT 0,
        error_message TEXT,
        created_at TIMESTAMP DEFAULT NOW(),
        UNIQUE(request_id, webhook_url)
      );
      
      CREATE INDEX IF NOT EXISTS idx_webhook_logs_request_id ON webhook_logs(request_id);
      CREATE INDEX IF NOT EXISTS idx_webhook_logs_sent_at ON webhook_logs(sent_at);
    `;

    try {
      await this.query(query);
      logger.info('Webhook logs table created/verified');
    } catch (error) {
      logger.error('Failed to create webhook logs table', { error });
      throw error;
    }
  }
}