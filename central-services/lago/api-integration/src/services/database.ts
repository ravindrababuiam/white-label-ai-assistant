import { Pool, PoolClient } from 'pg';
import { createLogger } from '../utils/logger';

const logger = createLogger('database');

export interface UsageEvent {
  id?: string;
  request_id: string;
  customer_external_id: string;
  model: string;
  provider: string;
  tokens_input: number;
  tokens_output: number;
  total_tokens: number;
  cost_usd: number;
  timestamp: Date;
  processed_at?: Date;
  lago_event_id?: string;
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
      port: parseInt(process.env.DB_PORT || '5433'),
      database: process.env.DB_NAME || 'lago',
      user: process.env.DB_USER || 'lago',
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

  // Usage Events Management
  async storeUsageEvent(event: UsageEvent): Promise<string> {
    const query = `
      INSERT INTO litellm_usage_events (
        request_id, customer_external_id, model, provider,
        tokens_input, tokens_output, total_tokens, cost_usd, timestamp
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
      ON CONFLICT (request_id) DO UPDATE SET
        customer_external_id = EXCLUDED.customer_external_id,
        model = EXCLUDED.model,
        provider = EXCLUDED.provider,
        tokens_input = EXCLUDED.tokens_input,
        tokens_output = EXCLUDED.tokens_output,
        total_tokens = EXCLUDED.total_tokens,
        cost_usd = EXCLUDED.cost_usd,
        timestamp = EXCLUDED.timestamp,
        updated_at = NOW()
      RETURNING id
    `;

    try {
      const result = await this.query(query, [
        event.request_id,
        event.customer_external_id,
        event.model,
        event.provider,
        event.tokens_input,
        event.tokens_output,
        event.total_tokens,
        event.cost_usd,
        event.timestamp
      ]);

      return result.rows[0].id;
    } catch (error) {
      logger.error('Failed to store usage event', { event, error });
      throw error;
    }
  }

  async markEventProcessed(requestId: string, lagoEventId?: string): Promise<void> {
    const query = `
      UPDATE litellm_usage_events 
      SET processed_at = NOW(), lago_event_id = $2, updated_at = NOW()
      WHERE request_id = $1
    `;

    try {
      await this.query(query, [requestId, lagoEventId]);
    } catch (error) {
      logger.error('Failed to mark event as processed', { requestId, lagoEventId, error });
      throw error;
    }
  }

  async getUnprocessedEvents(limit: number = 100): Promise<UsageEvent[]> {
    const query = `
      SELECT * FROM litellm_usage_events
      WHERE processed_at IS NULL
      ORDER BY timestamp ASC
      LIMIT $1
    `;

    try {
      const result = await this.query(query, [limit]);
      return result.rows.map(this.mapRowToUsageEvent);
    } catch (error) {
      logger.error('Failed to get unprocessed events', { error });
      throw error;
    }
  }

  async getCustomerUsageStats(
    customerExternalId: string,
    startDate: Date,
    endDate: Date
  ): Promise<any> {
    const query = `
      SELECT * FROM aggregate_customer_usage($1, $2, $3)
    `;

    try {
      const result = await this.query(query, [customerExternalId, startDate, endDate]);
      return result.rows;
    } catch (error) {
      logger.error('Failed to get customer usage stats', { customerExternalId, error });
      throw error;
    }
  }

  async getUsageEventsByCustomer(
    customerExternalId: string,
    startDate?: Date,
    endDate?: Date,
    limit: number = 100
  ): Promise<UsageEvent[]> {
    let query = `
      SELECT * FROM litellm_usage_events
      WHERE customer_external_id = $1
    `;
    const params: any[] = [customerExternalId];

    if (startDate) {
      query += ` AND timestamp >= $${params.length + 1}`;
      params.push(startDate);
    }

    if (endDate) {
      query += ` AND timestamp <= $${params.length + 1}`;
      params.push(endDate);
    }

    query += ` ORDER BY timestamp DESC LIMIT $${params.length + 1}`;
    params.push(limit);

    try {
      const result = await this.query(query, params);
      return result.rows.map(this.mapRowToUsageEvent);
    } catch (error) {
      logger.error('Failed to get usage events by customer', { customerExternalId, error });
      throw error;
    }
  }

  // Webhook Delivery Logs
  async logWebhookDelivery(
    webhookEndpointId: string,
    eventType: string,
    payload: any,
    httpStatus?: number,
    responseBody?: string
  ): Promise<void> {
    const query = `
      INSERT INTO webhook_delivery_logs (
        webhook_endpoint_id, event_type, payload, http_status, 
        response_body, delivered_at
      ) VALUES ($1, $2, $3, $4, $5, $6)
    `;

    try {
      await this.query(query, [
        webhookEndpointId,
        eventType,
        JSON.stringify(payload),
        httpStatus,
        responseBody,
        httpStatus ? new Date() : null
      ]);
    } catch (error) {
      logger.error('Failed to log webhook delivery', { 
        webhookEndpointId, 
        eventType, 
        httpStatus, 
        error 
      });
      // Don't throw here as this is just logging
    }
  }

  async getWebhookDeliveryStats(hours: number = 24): Promise<any> {
    const query = `
      SELECT 
        event_type,
        COUNT(*) as total_attempts,
        COUNT(CASE WHEN http_status BETWEEN 200 AND 299 THEN 1 END) as successful_deliveries,
        COUNT(CASE WHEN http_status >= 400 THEN 1 END) as failed_deliveries,
        AVG(retry_count) as avg_retry_count
      FROM webhook_delivery_logs
      WHERE created_at > NOW() - INTERVAL '${hours} hours'
      GROUP BY event_type
    `;

    try {
      const result = await this.query(query);
      return result.rows;
    } catch (error) {
      logger.error('Failed to get webhook delivery stats', { error });
      throw error;
    }
  }

  // Customer Management
  async getCustomerByExternalId(externalId: string): Promise<any> {
    const query = `
      SELECT * FROM customers WHERE external_id = $1
    `;

    try {
      const result = await this.query(query, [externalId]);
      return result.rows[0] || null;
    } catch (error) {
      logger.error('Failed to get customer by external ID', { externalId, error });
      throw error;
    }
  }

  async listCustomers(limit: number = 100, offset: number = 0): Promise<any[]> {
    const query = `
      SELECT * FROM customers
      ORDER BY created_at DESC
      LIMIT $1 OFFSET $2
    `;

    try {
      const result = await this.query(query, [limit, offset]);
      return result.rows;
    } catch (error) {
      logger.error('Failed to list customers', { error });
      throw error;
    }
  }

  // Organization Management
  async getCurrentOrganization(): Promise<any> {
    const query = `
      SELECT * FROM organizations LIMIT 1
    `;

    try {
      const result = await this.query(query);
      return result.rows[0] || null;
    } catch (error) {
      logger.error('Failed to get current organization', { error });
      throw error;
    }
  }

  private mapRowToUsageEvent(row: any): UsageEvent {
    return {
      id: row.id,
      request_id: row.request_id,
      customer_external_id: row.customer_external_id,
      model: row.model,
      provider: row.provider,
      tokens_input: row.tokens_input,
      tokens_output: row.tokens_output,
      total_tokens: row.total_tokens,
      cost_usd: parseFloat(row.cost_usd),
      timestamp: row.timestamp,
      processed_at: row.processed_at,
      lago_event_id: row.lago_event_id
    };
  }
}