import axios, { AxiosInstance } from 'axios';
import { createLogger } from '../utils/logger';

const logger = createLogger('lago-api');

export interface LagoOrganization {
  lago_id?: string;
  name: string;
  email: string;
  legal_name?: string;
  legal_number?: string;
  tax_identification_number?: string;
  address_line1?: string;
  address_line2?: string;
  city?: string;
  zipcode?: string;
  state?: string;
  country?: string;
  timezone?: string;
  webhook_url?: string;
  billing_configuration?: {
    invoice_grace_period?: number;
    payment_provider?: string;
    provider_customer_id?: string;
  };
}

export interface LagoCustomer {
  lago_id?: string;
  external_id: string;
  name?: string;
  firstname?: string;
  lastname?: string;
  email?: string;
  address_line1?: string;
  address_line2?: string;
  city?: string;
  zipcode?: string;
  state?: string;
  country?: string;
  legal_name?: string;
  legal_number?: string;
  tax_identification_number?: string;
  phone?: string;
  url?: string;
  billing_configuration?: {
    invoice_grace_period?: number;
    payment_provider?: string;
    provider_customer_id?: string;
    sync?: boolean;
    sync_with_provider?: boolean;
    document_locale?: string;
  };
  metadata?: Record<string, any>;
}

export interface LagoPlan {
  lago_id?: string;
  name: string;
  code: string;
  description?: string;
  interval: 'monthly' | 'yearly' | 'weekly' | 'quarterly';
  pay_in_advance?: boolean;
  amount_cents: number;
  amount_currency: string;
  trial_period?: number;
  charges?: LagoCharge[];
}

export interface LagoCharge {
  lago_id?: string;
  billable_metric_id: string;
  charge_model: 'standard' | 'graduated' | 'package' | 'percentage' | 'volume';
  pay_in_advance?: boolean;
  invoiceable?: boolean;
  min_amount_cents?: number;
  properties?: Record<string, any>;
  group_properties?: any[];
}

export interface LagoBillableMetric {
  lago_id?: string;
  name: string;
  code: string;
  description?: string;
  aggregation_type: 'count_agg' | 'sum_agg' | 'max_agg' | 'unique_count_agg';
  field_name?: string;
  group?: {
    key: string;
    values: string[];
  };
}

export interface LagoEvent {
  transaction_id: string;
  external_customer_id: string;
  code: string;
  timestamp?: number;
  properties?: Record<string, any>;
}

export class LagoApiService {
  private static instance: LagoApiService;
  private httpClient: AxiosInstance;
  private apiUrl: string;
  private apiKey: string;

  private constructor() {
    this.apiUrl = process.env.LAGO_API_URL || 'http://lago-api:3000';
    this.apiKey = process.env.LAGO_API_KEY || '';

    this.httpClient = axios.create({
      baseURL: `${this.apiUrl}/api/v1`,
      timeout: 30000,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.apiKey}`,
        'User-Agent': 'Lago-Integration-Service/1.0'
      }
    });

    // Add request/response interceptors for logging
    this.httpClient.interceptors.request.use(
      (config) => {
        logger.debug('Lago API request', {
          method: config.method,
          url: config.url,
          data: config.data
        });
        return config;
      },
      (error) => {
        logger.error('Lago API request error', { error });
        return Promise.reject(error);
      }
    );

    this.httpClient.interceptors.response.use(
      (response) => {
        logger.debug('Lago API response', {
          status: response.status,
          url: response.config.url
        });
        return response;
      },
      (error) => {
        logger.error('Lago API response error', {
          status: error.response?.status,
          statusText: error.response?.statusText,
          data: error.response?.data,
          url: error.config?.url
        });
        return Promise.reject(error);
      }
    );
  }

  static getInstance(): LagoApiService {
    if (!LagoApiService.instance) {
      LagoApiService.instance = new LagoApiService();
    }
    return LagoApiService.instance;
  }

  async initialize(): Promise<void> {
    try {
      // Test API connectivity
      await this.httpClient.get('/organizations/current');
      logger.info('Lago API service initialized successfully');
    } catch (error) {
      logger.error('Failed to initialize Lago API service', { error });
      throw error;
    }
  }

  // Organization Management
  async getCurrentOrganization(): Promise<LagoOrganization> {
    try {
      const response = await this.httpClient.get('/organizations/current');
      return response.data.organization;
    } catch (error) {
      logger.error('Failed to get current organization', { error });
      throw error;
    }
  }

  async updateOrganization(organization: Partial<LagoOrganization>): Promise<LagoOrganization> {
    try {
      const response = await this.httpClient.put('/organizations', {
        organization
      });
      return response.data.organization;
    } catch (error) {
      logger.error('Failed to update organization', { error });
      throw error;
    }
  }

  // Customer Management
  async createCustomer(customer: LagoCustomer): Promise<LagoCustomer> {
    try {
      const response = await this.httpClient.post('/customers', {
        customer
      });
      return response.data.customer;
    } catch (error) {
      logger.error('Failed to create customer', { customer, error });
      throw error;
    }
  }

  async getCustomer(externalId: string): Promise<LagoCustomer> {
    try {
      const response = await this.httpClient.get(`/customers/${externalId}`);
      return response.data.customer;
    } catch (error) {
      logger.error('Failed to get customer', { externalId, error });
      throw error;
    }
  }

  async updateCustomer(externalId: string, customer: Partial<LagoCustomer>): Promise<LagoCustomer> {
    try {
      const response = await this.httpClient.put(`/customers/${externalId}`, {
        customer
      });
      return response.data.customer;
    } catch (error) {
      logger.error('Failed to update customer', { externalId, customer, error });
      throw error;
    }
  }

  async deleteCustomer(externalId: string): Promise<void> {
    try {
      await this.httpClient.delete(`/customers/${externalId}`);
    } catch (error) {
      logger.error('Failed to delete customer', { externalId, error });
      throw error;
    }
  }

  async listCustomers(page: number = 1, perPage: number = 20): Promise<{ customers: LagoCustomer[]; meta: any }> {
    try {
      const response = await this.httpClient.get('/customers', {
        params: { page, per_page: perPage }
      });
      return {
        customers: response.data.customers,
        meta: response.data.meta
      };
    } catch (error) {
      logger.error('Failed to list customers', { error });
      throw error;
    }
  }

  // Billable Metrics Management
  async createBillableMetric(metric: LagoBillableMetric): Promise<LagoBillableMetric> {
    try {
      const response = await this.httpClient.post('/billable_metrics', {
        billable_metric: metric
      });
      return response.data.billable_metric;
    } catch (error) {
      logger.error('Failed to create billable metric', { metric, error });
      throw error;
    }
  }

  async getBillableMetric(code: string): Promise<LagoBillableMetric> {
    try {
      const response = await this.httpClient.get(`/billable_metrics/${code}`);
      return response.data.billable_metric;
    } catch (error) {
      logger.error('Failed to get billable metric', { code, error });
      throw error;
    }
  }

  async listBillableMetrics(): Promise<LagoBillableMetric[]> {
    try {
      const response = await this.httpClient.get('/billable_metrics');
      return response.data.billable_metrics;
    } catch (error) {
      logger.error('Failed to list billable metrics', { error });
      throw error;
    }
  }

  // Plan Management
  async createPlan(plan: LagoPlan): Promise<LagoPlan> {
    try {
      const response = await this.httpClient.post('/plans', {
        plan
      });
      return response.data.plan;
    } catch (error) {
      logger.error('Failed to create plan', { plan, error });
      throw error;
    }
  }

  async getPlan(code: string): Promise<LagoPlan> {
    try {
      const response = await this.httpClient.get(`/plans/${code}`);
      return response.data.plan;
    } catch (error) {
      logger.error('Failed to get plan', { code, error });
      throw error;
    }
  }

  async listPlans(): Promise<LagoPlan[]> {
    try {
      const response = await this.httpClient.get('/plans');
      return response.data.plans;
    } catch (error) {
      logger.error('Failed to list plans', { error });
      throw error;
    }
  }

  // Subscription Management
  async createSubscription(subscription: {
    external_customer_id: string;
    plan_code: string;
    external_id?: string;
    name?: string;
    billing_time?: 'calendar' | 'anniversary';
    subscription_at?: string;
    ending_at?: string;
  }): Promise<any> {
    try {
      const response = await this.httpClient.post('/subscriptions', {
        subscription
      });
      return response.data.subscription;
    } catch (error) {
      logger.error('Failed to create subscription', { subscription, error });
      throw error;
    }
  }

  async getSubscription(externalId: string): Promise<any> {
    try {
      const response = await this.httpClient.get(`/subscriptions/${externalId}`);
      return response.data.subscription;
    } catch (error) {
      logger.error('Failed to get subscription', { externalId, error });
      throw error;
    }
  }

  // Event Management
  async sendEvent(event: LagoEvent): Promise<void> {
    try {
      await this.httpClient.post('/events', {
        event
      });
      logger.info('Event sent successfully', { 
        transactionId: event.transaction_id,
        customerId: event.external_customer_id,
        code: event.code
      });
    } catch (error) {
      logger.error('Failed to send event', { event, error });
      throw error;
    }
  }

  async sendBatchEvents(events: LagoEvent[]): Promise<void> {
    try {
      await this.httpClient.post('/events/batch', {
        events
      });
      logger.info('Batch events sent successfully', { count: events.length });
    } catch (error) {
      logger.error('Failed to send batch events', { count: events.length, error });
      throw error;
    }
  }

  // Invoice Management
  async getInvoices(externalCustomerId?: string, page: number = 1, perPage: number = 20): Promise<any> {
    try {
      const params: any = { page, per_page: perPage };
      if (externalCustomerId) {
        params.external_customer_id = externalCustomerId;
      }

      const response = await this.httpClient.get('/invoices', { params });
      return {
        invoices: response.data.invoices,
        meta: response.data.meta
      };
    } catch (error) {
      logger.error('Failed to get invoices', { externalCustomerId, error });
      throw error;
    }
  }

  async getInvoice(lagoId: string): Promise<any> {
    try {
      const response = await this.httpClient.get(`/invoices/${lagoId}`);
      return response.data.invoice;
    } catch (error) {
      logger.error('Failed to get invoice', { lagoId, error });
      throw error;
    }
  }

  // Usage Analytics
  async getCustomerUsage(externalCustomerId: string, subscriptionId?: string): Promise<any> {
    try {
      const params: any = {};
      if (subscriptionId) {
        params.subscription_id = subscriptionId;
      }

      const response = await this.httpClient.get(`/customers/${externalCustomerId}/current_usage`, {
        params
      });
      return response.data;
    } catch (error) {
      logger.error('Failed to get customer usage', { externalCustomerId, error });
      throw error;
    }
  }
}