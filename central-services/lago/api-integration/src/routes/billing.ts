import { Router, Request, Response } from 'express';
import Joi from 'joi';
import { LagoApiService } from '../services/lago-api';
import { DatabaseService } from '../services/database';
import { createLogger } from '../utils/logger';

const logger = createLogger('billing-routes');
const router = Router();

// Validation schemas
const planCreateSchema = Joi.object({
  name: Joi.string().required().min(1).max(255),
  code: Joi.string().required().min(1).max(100),
  description: Joi.string().optional().max(500),
  interval: Joi.string().valid('monthly', 'yearly', 'weekly', 'quarterly').required(),
  pay_in_advance: Joi.boolean().optional(),
  amount_cents: Joi.number().integer().min(0).required(),
  amount_currency: Joi.string().length(3).required(),
  trial_period: Joi.number().integer().min(0).optional(),
  charges: Joi.array().items(Joi.object({
    billable_metric_id: Joi.string().required(),
    charge_model: Joi.string().valid('standard', 'graduated', 'package', 'percentage', 'volume').required(),
    pay_in_advance: Joi.boolean().optional(),
    invoiceable: Joi.boolean().optional(),
    min_amount_cents: Joi.number().integer().min(0).optional(),
    properties: Joi.object().optional()
  })).optional()
});

const billableMetricCreateSchema = Joi.object({
  name: Joi.string().required().min(1).max(255),
  code: Joi.string().required().min(1).max(100),
  description: Joi.string().optional().max(500),
  aggregation_type: Joi.string().valid('count_agg', 'sum_agg', 'max_agg', 'unique_count_agg').required(),
  field_name: Joi.string().optional().max(100),
  group: Joi.object({
    key: Joi.string().required(),
    values: Joi.array().items(Joi.string()).required()
  }).optional()
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

// GET /api/billing/plans - List all plans
router.get('/plans', async (req: Request, res: Response) => {
  try {
    const lagoService = LagoApiService.getInstance();

    logger.debug('Listing billing plans');

    const plans = await lagoService.listPlans();

    res.json({
      plans
    });

  } catch (error) {
    logger.error('Failed to list plans', { error: error.message });

    res.status(500).json({
      error: 'Failed to list plans'
    });
  }
});

// POST /api/billing/plans - Create new plan
router.post('/plans', validateRequest(planCreateSchema), async (req: Request, res: Response) => {
  try {
    const lagoService = LagoApiService.getInstance();

    logger.info('Creating new billing plan', {
      name: req.body.name,
      code: req.body.code,
      interval: req.body.interval
    });

    const plan = await lagoService.createPlan(req.body);

    logger.info('Billing plan created successfully', {
      planId: plan.lago_id,
      code: plan.code
    });

    res.status(201).json({
      plan
    });

  } catch (error) {
    logger.error('Failed to create plan', { 
      error: error.message,
      planData: req.body
    });

    if (error.response?.status === 422) {
      res.status(422).json({
        error: 'Plan validation failed',
        details: error.response.data
      });
    } else {
      res.status(500).json({
        error: 'Failed to create plan'
      });
    }
  }
});

// GET /api/billing/plans/:code - Get plan by code
router.get('/plans/:code', async (req: Request, res: Response) => {
  try {
    const lagoService = LagoApiService.getInstance();
    const code = req.params.code;

    logger.debug('Getting billing plan', { code });

    const plan = await lagoService.getPlan(code);

    res.json({
      plan
    });

  } catch (error) {
    logger.error('Failed to get plan', { 
      code: req.params.code,
      error: error.message 
    });

    if (error.response?.status === 404) {
      res.status(404).json({
        error: 'Plan not found'
      });
    } else {
      res.status(500).json({
        error: 'Failed to get plan'
      });
    }
  }
});

// GET /api/billing/metrics - List all billable metrics
router.get('/metrics', async (req: Request, res: Response) => {
  try {
    const lagoService = LagoApiService.getInstance();

    logger.debug('Listing billable metrics');

    const metrics = await lagoService.listBillableMetrics();

    res.json({
      billable_metrics: metrics
    });

  } catch (error) {
    logger.error('Failed to list billable metrics', { error: error.message });

    res.status(500).json({
      error: 'Failed to list billable metrics'
    });
  }
});

// POST /api/billing/metrics - Create new billable metric
router.post('/metrics', validateRequest(billableMetricCreateSchema), async (req: Request, res: Response) => {
  try {
    const lagoService = LagoApiService.getInstance();

    logger.info('Creating new billable metric', {
      name: req.body.name,
      code: req.body.code,
      aggregationType: req.body.aggregation_type
    });

    const metric = await lagoService.createBillableMetric(req.body);

    logger.info('Billable metric created successfully', {
      metricId: metric.lago_id,
      code: metric.code
    });

    res.status(201).json({
      billable_metric: metric
    });

  } catch (error) {
    logger.error('Failed to create billable metric', { 
      error: error.message,
      metricData: req.body
    });

    if (error.response?.status === 422) {
      res.status(422).json({
        error: 'Billable metric validation failed',
        details: error.response.data
      });
    } else {
      res.status(500).json({
        error: 'Failed to create billable metric'
      });
    }
  }
});

// GET /api/billing/metrics/:code - Get billable metric by code
router.get('/metrics/:code', async (req: Request, res: Response) => {
  try {
    const lagoService = LagoApiService.getInstance();
    const code = req.params.code;

    logger.debug('Getting billable metric', { code });

    const metric = await lagoService.getBillableMetric(code);

    res.json({
      billable_metric: metric
    });

  } catch (error) {
    logger.error('Failed to get billable metric', { 
      code: req.params.code,
      error: error.message 
    });

    if (error.response?.status === 404) {
      res.status(404).json({
        error: 'Billable metric not found'
      });
    } else {
      res.status(500).json({
        error: 'Failed to get billable metric'
      });
    }
  }
});

// GET /api/billing/invoices - List invoices
router.get('/invoices', async (req: Request, res: Response) => {
  try {
    const lagoService = LagoApiService.getInstance();
    const externalCustomerId = req.query.external_customer_id as string;
    const page = parseInt(req.query.page as string) || 1;
    const perPage = Math.min(parseInt(req.query.per_page as string) || 20, 100);

    logger.debug('Listing invoices', { externalCustomerId, page, perPage });

    const result = await lagoService.getInvoices(externalCustomerId, page, perPage);

    res.json(result);

  } catch (error) {
    logger.error('Failed to list invoices', { error: error.message });

    res.status(500).json({
      error: 'Failed to list invoices'
    });
  }
});

// GET /api/billing/invoices/:lago_id - Get invoice by Lago ID
router.get('/invoices/:lago_id', async (req: Request, res: Response) => {
  try {
    const lagoService = LagoApiService.getInstance();
    const lagoId = req.params.lago_id;

    logger.debug('Getting invoice', { lagoId });

    const invoice = await lagoService.getInvoice(lagoId);

    res.json({
      invoice
    });

  } catch (error) {
    logger.error('Failed to get invoice', { 
      lagoId: req.params.lago_id,
      error: error.message 
    });

    if (error.response?.status === 404) {
      res.status(404).json({
        error: 'Invoice not found'
      });
    } else {
      res.status(500).json({
        error: 'Failed to get invoice'
      });
    }
  }
});

// GET /api/billing/usage/:external_customer_id - Get customer usage
router.get('/usage/:external_customer_id', async (req: Request, res: Response) => {
  try {
    const lagoService = LagoApiService.getInstance();
    const dbService = DatabaseService.getInstance();
    const externalCustomerId = req.params.external_customer_id;
    const subscriptionId = req.query.subscription_id as string;

    logger.debug('Getting customer usage', { externalCustomerId, subscriptionId });

    // Get current usage from Lago
    const currentUsage = await lagoService.getCustomerUsage(externalCustomerId, subscriptionId);

    // Get historical usage from local database
    const endDate = new Date();
    const startDate = new Date(endDate.getTime() - 30 * 24 * 60 * 60 * 1000); // 30 days ago
    
    const historicalUsage = await dbService.getCustomerUsageStats(externalCustomerId, startDate, endDate);

    res.json({
      current_usage: currentUsage,
      historical_usage: historicalUsage,
      period: {
        start_date: startDate.toISOString(),
        end_date: endDate.toISOString()
      }
    });

  } catch (error) {
    logger.error('Failed to get customer usage', { 
      externalCustomerId: req.params.external_customer_id,
      error: error.message 
    });

    if (error.response?.status === 404) {
      res.status(404).json({
        error: 'Customer not found'
      });
    } else {
      res.status(500).json({
        error: 'Failed to get customer usage'
      });
    }
  }
});

// GET /api/billing/analytics - Get billing analytics
router.get('/analytics', async (req: Request, res: Response) => {
  try {
    const lagoService = LagoApiService.getInstance();
    const dbService = DatabaseService.getInstance();

    const days = parseInt(req.query.days as string) || 30;
    const endDate = new Date();
    const startDate = new Date(endDate.getTime() - days * 24 * 60 * 60 * 1000);

    logger.debug('Getting billing analytics', { days, startDate, endDate });

    // Get recent invoices
    const invoicesResult = await lagoService.getInvoices(undefined, 1, 100);
    const recentInvoices = invoicesResult.invoices || [];

    // Calculate analytics from invoices
    const totalRevenue = recentInvoices.reduce((sum: number, invoice: any) => {
      if (invoice.status === 'finalized' && new Date(invoice.issuing_date) >= startDate) {
        return sum + (invoice.total_amount_cents / 100);
      }
      return sum;
    }, 0);

    const invoicesByStatus = recentInvoices.reduce((acc: any, invoice: any) => {
      acc[invoice.status] = (acc[invoice.status] || 0) + 1;
      return acc;
    }, {});

    // Get webhook delivery stats
    const webhookStats = await dbService.getWebhookDeliveryStats(days * 24);

    const analytics = {
      period: {
        start_date: startDate.toISOString(),
        end_date: endDate.toISOString(),
        days
      },
      revenue: {
        total_amount: totalRevenue,
        currency: 'USD', // Could be made dynamic
        invoice_count: recentInvoices.length
      },
      invoices: {
        by_status: invoicesByStatus,
        recent: recentInvoices.slice(0, 10).map((invoice: any) => ({
          lago_id: invoice.lago_id,
          number: invoice.number,
          status: invoice.status,
          total_amount_cents: invoice.total_amount_cents,
          currency: invoice.currency,
          issuing_date: invoice.issuing_date,
          customer_name: invoice.customer?.name
        }))
      },
      webhooks: webhookStats,
      timestamp: new Date().toISOString()
    };

    res.json(analytics);

  } catch (error) {
    logger.error('Failed to get billing analytics', { error: error.message });

    res.status(500).json({
      error: 'Failed to get billing analytics'
    });
  }
});

export { router as billingRoutes };