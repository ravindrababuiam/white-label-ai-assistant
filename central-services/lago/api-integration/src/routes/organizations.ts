import { Router, Request, Response } from 'express';
import Joi from 'joi';
import { LagoApiService } from '../services/lago-api';
import { DatabaseService } from '../services/database';
import { createLogger } from '../utils/logger';

const logger = createLogger('organizations-routes');
const router = Router();

// Validation schemas
const organizationUpdateSchema = Joi.object({
  name: Joi.string().min(1).max(255).optional(),
  email: Joi.string().email().optional(),
  legal_name: Joi.string().max(255).optional(),
  legal_number: Joi.string().max(100).optional(),
  tax_identification_number: Joi.string().max(100).optional(),
  address_line1: Joi.string().max(255).optional(),
  address_line2: Joi.string().max(255).optional(),
  city: Joi.string().max(100).optional(),
  zipcode: Joi.string().max(20).optional(),
  state: Joi.string().max(100).optional(),
  country: Joi.string().max(100).optional(),
  timezone: Joi.string().max(50).optional(),
  webhook_url: Joi.string().uri().optional(),
  billing_configuration: Joi.object({
    invoice_grace_period: Joi.number().integer().min(0).optional(),
    payment_provider: Joi.string().valid('stripe', 'gocardless', 'adyen').optional(),
    provider_customer_id: Joi.string().optional()
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

// GET /api/organizations/current - Get current organization
router.get('/current', async (req: Request, res: Response) => {
  try {
    const lagoService = LagoApiService.getInstance();
    const dbService = DatabaseService.getInstance();

    // Get organization from Lago API
    const lagoOrganization = await lagoService.getCurrentOrganization();
    
    // Get additional data from local database
    const localOrganization = await dbService.getCurrentOrganization();

    const organization = {
      ...lagoOrganization,
      local_data: localOrganization
    };

    logger.info('Retrieved current organization', {
      organizationId: organization.lago_id,
      name: organization.name
    });

    res.json({
      organization
    });

  } catch (error) {
    logger.error('Failed to get current organization', { error: error.message });

    res.status(500).json({
      error: 'Failed to get current organization'
    });
  }
});

// PUT /api/organizations/current - Update current organization
router.put('/current', validateRequest(organizationUpdateSchema), async (req: Request, res: Response) => {
  try {
    const lagoService = LagoApiService.getInstance();

    logger.info('Updating organization', {
      updates: Object.keys(req.body)
    });

    const updatedOrganization = await lagoService.updateOrganization(req.body);

    logger.info('Organization updated successfully', {
      organizationId: updatedOrganization.lago_id,
      name: updatedOrganization.name
    });

    res.json({
      organization: updatedOrganization
    });

  } catch (error) {
    logger.error('Failed to update organization', { 
      error: error.message,
      updates: req.body
    });

    res.status(500).json({
      error: 'Failed to update organization'
    });
  }
});

// GET /api/organizations/stats - Get organization statistics
router.get('/stats', async (req: Request, res: Response) => {
  try {
    const dbService = DatabaseService.getInstance();
    const lagoService = LagoApiService.getInstance();

    // Get customer count
    const customersResult = await lagoService.listCustomers(1, 1);
    const totalCustomers = customersResult.meta?.total_count || 0;

    // Get recent usage statistics
    const endDate = new Date();
    const startDate = new Date(endDate.getTime() - 30 * 24 * 60 * 60 * 1000); // 30 days ago

    // Get webhook delivery stats
    const webhookStats = await dbService.getWebhookDeliveryStats(24);

    // Get recent invoices
    const invoicesResult = await lagoService.getInvoices(undefined, 1, 10);
    const recentInvoices = invoicesResult.invoices || [];

    const stats = {
      customers: {
        total: totalCustomers,
        active: totalCustomers // Simplified - could be enhanced with active customer logic
      },
      webhooks: {
        last_24h: webhookStats.reduce((acc: any, stat: any) => {
          acc.total_attempts += stat.total_attempts || 0;
          acc.successful_deliveries += stat.successful_deliveries || 0;
          acc.failed_deliveries += stat.failed_deliveries || 0;
          return acc;
        }, { total_attempts: 0, successful_deliveries: 0, failed_deliveries: 0 })
      },
      invoices: {
        recent_count: recentInvoices.length,
        recent_invoices: recentInvoices.slice(0, 5).map((invoice: any) => ({
          lago_id: invoice.lago_id,
          number: invoice.number,
          status: invoice.status,
          total_amount_cents: invoice.total_amount_cents,
          currency: invoice.currency,
          issuing_date: invoice.issuing_date
        }))
      },
      timestamp: new Date().toISOString()
    };

    logger.info('Retrieved organization statistics', {
      totalCustomers,
      recentInvoicesCount: recentInvoices.length
    });

    res.json(stats);

  } catch (error) {
    logger.error('Failed to get organization statistics', { error: error.message });

    res.status(500).json({
      error: 'Failed to get organization statistics'
    });
  }
});

// POST /api/organizations/setup - Initial organization setup
router.post('/setup', async (req: Request, res: Response) => {
  try {
    const lagoService = LagoApiService.getInstance();

    logger.info('Starting organization setup');

    // Create default billable metrics for AI usage
    const aiUsageMetric = await lagoService.createBillableMetric({
      name: 'AI Usage',
      code: 'ai_usage',
      description: 'AI model usage tracking for tokens and requests',
      aggregation_type: 'sum_agg',
      field_name: 'total_tokens'
    });

    // Create default plan for AI usage
    const defaultPlan = await lagoService.createPlan({
      name: 'AI Usage Plan',
      code: 'ai_usage_plan',
      description: 'Usage-based pricing for AI services',
      interval: 'monthly',
      amount_cents: 0, // Base fee
      amount_currency: 'USD',
      charges: [{
        billable_metric_id: aiUsageMetric.lago_id!,
        charge_model: 'standard',
        properties: {
          amount: '0.001' // $0.001 per token
        }
      }]
    });

    logger.info('Organization setup completed', {
      metricId: aiUsageMetric.lago_id,
      planId: defaultPlan.lago_id
    });

    res.json({
      message: 'Organization setup completed successfully',
      billable_metric: aiUsageMetric,
      default_plan: defaultPlan
    });

  } catch (error) {
    logger.error('Failed to setup organization', { error: error.message });

    res.status(500).json({
      error: 'Failed to setup organization'
    });
  }
});

export { router as organizationRoutes };