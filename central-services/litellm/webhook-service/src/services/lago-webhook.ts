import axios, { AxiosInstance } from 'axios';
import { createLogger } from '../utils/logger';
import { UsageRecord } from './database';

const logger = createLogger('lago-webhook');

export interface LagoUsageEvent {
  event_type: 'usage';
  timestamp: number;
  customer_id: string;
  model: string;
  provider: string;
  tokens_input: number;
  tokens_output: number;
  total_tokens: number;
  cost_usd: number;
  request_id: string;
  api_key_hash: string;
  metadata: {
    user_id?: string;
    team_id?: string;
    request_tags?: any;
  };
}

export class LagoWebhookService {
  private static instance: LagoWebhookService;
  private httpClient: AxiosInstance;
  private webhookUrl: string;
  private apiKey: string;

  private constructor() {
    this.webhookUrl = process.env.LAGO_WEBHOOK_URL || 'http://lago:3000/webhooks/litellm';
    this.apiKey = process.env.LAGO_API_KEY || '';

    this.httpClient = axios.create({
      timeout: 10000,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.apiKey}`,
        'User-Agent': 'LiteLLM-Webhook-Service/1.0'
      }
    });

    // Add request/response interceptors for logging
    this.httpClient.interceptors.request.use(
      (config) => {
        logger.debug('Sending webhook request', {
          url: config.url,
          method: config.method,
          headers: config.headers
        });
        return config;
      },
      (error) => {
        logger.error('Webhook request error', { error });
        return Promise.reject(error);
      }
    );

    this.httpClient.interceptors.response.use(
      (response) => {
        logger.debug('Webhook response received', {
          status: response.status,
          statusText: response.statusText
        });
        return response;
      },
      (error) => {
        logger.error('Webhook response error', {
          status: error.response?.status,
          statusText: error.response?.statusText,
          data: error.response?.data
        });
        return Promise.reject(error);
      }
    );
  }

  static getInstance(): LagoWebhookService {
    if (!LagoWebhookService.instance) {
      LagoWebhookService.instance = new LagoWebhookService();
    }
    return LagoWebhookService.instance;
  }

  async initialize(): Promise<void> {
    // Test webhook endpoint connectivity
    try {
      await this.testConnection();
      logger.info('Lago webhook service initialized successfully');
    } catch (error) {
      logger.warn('Failed to connect to Lago webhook endpoint', { error });
      // Don't throw here - service should still start even if Lago is temporarily unavailable
    }
  }

  private async testConnection(): Promise<void> {
    const testUrl = this.webhookUrl.replace('/webhooks/litellm', '/health');
    
    try {
      await this.httpClient.get(testUrl, { timeout: 5000 });
      logger.info('Lago health check passed');
    } catch (error) {
      logger.warn('Lago health check failed', { error: error.message });
      throw error;
    }
  }

  async sendUsageEvent(usageRecord: UsageRecord): Promise<boolean> {
    try {
      const event = this.transformUsageRecord(usageRecord);
      
      logger.info('Sending usage event to Lago', {
        requestId: event.request_id,
        customerId: event.customer_id,
        model: event.model,
        totalTokens: event.total_tokens,
        cost: event.cost_usd
      });

      const response = await this.httpClient.post(this.webhookUrl, event);
      
      if (response.status >= 200 && response.status < 300) {
        logger.info('Usage event sent successfully', {
          requestId: event.request_id,
          status: response.status
        });
        return true;
      } else {
        logger.error('Unexpected response status', {
          requestId: event.request_id,
          status: response.status,
          data: response.data
        });
        return false;
      }
    } catch (error) {
      logger.error('Failed to send usage event', {
        requestId: usageRecord.request_id,
        error: error.message,
        stack: error.stack
      });
      return false;
    }
  }

  private transformUsageRecord(record: UsageRecord): LagoUsageEvent {
    return {
      event_type: 'usage',
      timestamp: Math.floor(record.startTime.getTime() / 1000),
      customer_id: record.end_user,
      model: record.model,
      provider: record.custom_llm_provider || 'unknown',
      tokens_input: record.prompt_tokens,
      tokens_output: record.completion_tokens,
      total_tokens: record.total_tokens,
      cost_usd: record.spend,
      request_id: record.request_id,
      api_key_hash: this.hashApiKey(record.api_key),
      metadata: {
        user_id: record.user,
        team_id: record.team_id,
        request_tags: record.request_tags
      }
    };
  }

  private hashApiKey(apiKey: string): string {
    // Simple hash for privacy - in production, use a proper hashing algorithm
    if (!apiKey) return 'unknown';
    
    const hash = apiKey.split('').reduce((a, b) => {
      a = ((a << 5) - a) + b.charCodeAt(0);
      return a & a;
    }, 0);
    
    return `key_${Math.abs(hash).toString(16)}`;
  }

  async sendBatchUsageEvents(records: UsageRecord[]): Promise<{ success: number; failed: number }> {
    let success = 0;
    let failed = 0;

    logger.info('Sending batch usage events', { count: records.length });

    // Process in parallel with concurrency limit
    const concurrency = 5;
    const chunks = [];
    
    for (let i = 0; i < records.length; i += concurrency) {
      chunks.push(records.slice(i, i + concurrency));
    }

    for (const chunk of chunks) {
      const promises = chunk.map(async (record) => {
        const result = await this.sendUsageEvent(record);
        return result ? 'success' : 'failed';
      });

      const results = await Promise.all(promises);
      success += results.filter(r => r === 'success').length;
      failed += results.filter(r => r === 'failed').length;
    }

    logger.info('Batch processing completed', { success, failed, total: records.length });
    return { success, failed };
  }

  async validateWebhookEndpoint(): Promise<boolean> {
    try {
      await this.testConnection();
      return true;
    } catch (error) {
      return false;
    }
  }
}