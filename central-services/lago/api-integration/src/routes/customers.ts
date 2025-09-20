import { Router, Request, Response } from 'express';
import Joi from 'joi';
import { LagoApiService, LagoCustomer } from '../services/lago-api';
import { DatabaseService } from '../services/database';
import { createLogger } from '../utils/logger';

const logger = createLogger('customers-routes');
const router = Router();

// Validation schemas
const customerCreateSchema = Joi.object({
  external_id: Joi.string().required().min(1).max(255),
  name: Joi.string().optional().max(255),
  firstname: Joi.string().optional().max(100),
  lastname: Joi.string().optional().max(100),
  email: Joi.string().email().optional(),
  address_line1: Joi.string().optional().max(255),
  address_line2: Joi.string().optional().max(255),
  city: Joi.string().optional().max(100),
  zipcode: Joi.string().optional().max(20),
  state: Joi.string().optional().max(100),
  country: Joi.string().optional().max(100),
  legal_name: Joi.string().optional().max(255),
  legal_number: Joi.string().optional().max(100),
  tax_identification_number: Joi.string().optional().max(100),
  phone: Joi.string().optional().max(50),
  url: Joi.string().uri().optional(),
  billing_configuration: Joi.object({
    invoice_grace_period: Joi.number().integer().min(0).optional(),
    payment_provider: Joi.string().valid('stripe', 'gocardless', 'adyen').optional(),
    provider_customer_id: Joi.string().optional(),
    sync: Joi.boolean().optional(),
    sync_with_provider: Joi.boolean().optional(),
    document_locale: Joi.string().optional()
  }).optional(),
  metadata: Joi.object().optional(),
  plan_code: Joi.string().optional() // For automatic subscription creation
});

const customerUpdateSchema = customerCreateSchema.fork(['external_id'], (schema) => schema.optional());

const subscriptionCreateSchema = Joi.object({
  plan_code: Joi.string().required(),
  external_id: Joi.string().optional(),
  name: Joi.string().optional(),
  billing_time: Joi.string().valid('calendar', 'anniversary').optional(),
  subscription_at: Joi.date().iso().optional(),
  ending_at: Joi.date().iso().optional()
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

// POST /api/customers - Create new customer
router.post('/', validateRequest(customerCreateSchema), async (req: Request, res: Response) => {
  try {
    const lagoService = LagoApiService.getInstance();
    const { plan_code, ...customerData } = req.body;

    logger.info('Creating new customer', {
      externalId: customerData.external_id,
      name: customerData.name,
      email: customerData.email
    });

    // Create customer in Lago
    const customer = await lagoService.createCustomer(customerData);

    // Create subscription if plan_code is provided
    let subscription = null;
    if (plan_code) {
      try {
        subscription = await lagoService.createSubscription({
          external_customer_id: customer.external_id,
          plan_code: plan_code
        });
        logger.info('Subscription created for customer', {
          customerId: customer.external_id,
          planCode: plan_code,
          subscriptionId: subscription.lago_id
        });
      } catch (subscriptionError) {
        logger.warn('Failed to create subscription for customer', {
          customerId: customer.external_id,
          planCode: plan_code,
          error: subscriptionError.message
        });
      }
    }

    logger.info('Customer created successfully', {
      customerId: customer.lago_id,
      externalId: customer.external_id
    });

    res.status(201).json({
      customer,
      subscription
    });

  } catch (error) {
    logger.error('Failed to create customer', { 
      error: error.message,
      customerData: req.body
    });

    if (error.response?.status === 422) {
      res.status(422).json({
        error: 'Customer validation failed',
        details: error.response.data
      });
    } else {
      res.status(500).json({
        error: 'Failed to create customer'
      });
    }
  }
});

// GET /api/customers - List customers
router.get('/', async (req: Request, res: Response) => {
  try {
    const lagoService = LagoApiService.getInstance();
    const page = parseInt(req.query.page as string) || 1;
    const perPage = Math.min(parseInt(req.query.per_page as string) || 20, 100);

    logger.debug('Listing customers', { page, perPage });

    const result = await lagoService.listCustomers(page, perPage);

    res.json(result);

  } catch (error) {
    logger.error('Failed to list customers', { error: error.message });

    res.status(500).json({
      error: 'Failed to list customers'
    });
  }
});

// GET /api/customers/:external_id - Get customer by external ID
router.get('/:external_id', async (req: Request, res: Response) => {
  try {
    const lagoService = LagoApiService.getInstance();
    const dbService = DatabaseService.getInstance();
    const externalId = req.params.external_id;

    logger.debug('Getting customer', { externalId });

    // Get customer from Lago
    const customer = await lagoService.getCustomer(externalId);

    // Get usage statistics from local database
    const endDate = new Date();
    const startDate = new Date(endDate.getTime() - 30 * 24 * 60 * 60 * 1000); // 30 days ago
    
    const usageStats = await dbService.getCustomerUsageStats(externalId, startDate, endDate);
    const recentEvents = await dbService.getUsageEventsByCustomer(externalId, startDate, endDate, 10);

    // Get current usage from Lago
    let currentUsage = null;
    try {
      currentUsage = await lagoService.getCustomerUsage(externalId);
    } catch (usageError) {
      logger.warn('Failed to get current usage for customer', {
        externalId,
        error: usageError.message
      });
    }

    res.json({
      customer,
      usage_stats: usageStats,
      recent_events: recentEvents,
      current_usage: currentUsage
    });

  } catch (error) {
    logger.error('Failed to get customer', { 
      externalId: req.params.external_id,
      error: error.message 
    });

    if (error.response?.status === 404) {
      res.status(404).json({
        error: 'Customer not found'
      });
    } else {
      res.status(500).json({
        error: 'Failed to get customer'
      });
    }
  }
});

// PUT /api/customers/:external_id - Update customer
router.put('/:external_id', validateRequest(customerUpdateSchema), async (req: Request, res: Response) => {
  try {
    const lagoService = LagoApiService.getInstance();
    const externalId = req.params.external_id;

    logger.info('Updating customer', {
      externalId,
      updates: Object.keys(req.body)
    });

    const customer = await lagoService.updateCustomer(externalId, req.body);

    logger.info('Customer updated successfully', {
      customerId: customer.lago_id,
      externalId: customer.external_id
    });

    res.json({
      customer
    });

  } catch (error) {
    logger.error('Failed to update customer', { 
      externalId: req.params.external_id,
      error: error.message,
      updates: req.body
    });

    if (error.response?.status === 404) {
      res.status(404).json({
        error: 'Customer not found'
      });
    } else if (error.response?.status === 422) {
      res.status(422).json({
        error: 'Customer validation failed',
        details: error.response.data
      });
    } else {
      res.status(500).json({
        error: 'Failed to update customer'
      });
    }
  }
});

// DELETE /api/customers/:external_id - Delete customer
router.delete('/:external_id', async (req: Request, res: Response) => {
  try {
    const lagoService = LagoApiService.getInstance();
    const externalId = req.params.external_id;

    logger.info('Deleting customer', { externalId });

    await lagoService.deleteCustomer(externalId);

    logger.info('Customer deleted successfully', { externalId });

    res.status(204).send();

  } catch (error) {
    logger.error('Failed to delete customer', { 
      externalId: req.params.external_id,
      error: error.message 
    });

    if (error.response?.status === 404) {
      res.status(404).json({
        error: 'Customer not found'
      });
    } else {
      res.status(500).json({
        error: 'Failed to delete customer'
      });
    }
  }
});

// POST /api/customers/:external_id/subscriptions - Create subscription for customer
router.post('/:external_id/subscriptions', validateRequest(subscriptionCreateSchema), async (req: Request, res: Response) => {
  try {
    const lagoService = LagoApiService.getInstance();
    const externalId = req.params.external_id;

    logger.info('Creating subscription for customer', {
      externalId,
      planCode: req.body.plan_code
    });

    const subscription = await lagoService.createSubscription({
      external_customer_id: externalId,
      ...req.body
    });

    logger.info('Subscription created successfully', {
      customerId: externalId,
      subscriptionId: subscription.lago_id,
      planCode: req.body.plan_code
    });

    res.status(201).json({
      subscription
    });

  } catch (error) {
    logger.error('Failed to create subscription', { 
      externalId: req.params.external_id,
      planCode: req.body.plan_code,
      error: error.message 
    });

    if (error.response?.status === 422) {
      res.status(422).json({
        error: 'Subscription validation failed',
        details: error.response.data
      });
    } else {
      res.status(500).json({
        error: 'Failed to create subscription'
      });
    }
  }
});

// GET /api/customers/:external_id/usage - Get customer usage
router.get('/:external_id/usage', async (req: Request, res: Response) => {
  try {
    const lagoService = LagoApiService.getInstance();
    const dbService = DatabaseService.getInstance();
    const externalId = req.params.external_id;
    
    const startDate = req.query.start_date ? new Date(req.query.start_date as string) : 
                     new Date(Date.now() - 30 * 24 * 60 * 60 * 1000); // 30 days ago
    const endDate = req.query.end_date ? new Date(req.query.end_date as string) : new Date();

    logger.debug('Getting customer usage', { externalId, startDate, endDate });

    // Get usage from local database
    const usageStats = await dbService.getCustomerUsageStats(externalId, startDate, endDate);
    const usageEvents = await dbService.getUsageEventsByCustomer(externalId, startDate, endDate, 100);

    // Get current usage from Lago
    let currentUsage = null;
    try {
      currentUsage = await lagoService.getCustomerUsage(externalId);
    } catch (usageError) {
      logger.warn('Failed to get current usage from Lago', {
        externalId,
        error: usageError.message
      });
    }

    res.json({
      period: {
        start_date: startDate.toISOString(),
        end_date: endDate.toISOString()
      },
      usage_stats: usageStats,
      usage_events: usageEvents,
      current_usage: currentUsage
    });

  } catch (error) {
    logger.error('Failed to get customer usage', { 
      externalId: req.params.external_id,
      error: error.message 
    });

    res.status(500).json({
      error: 'Failed to get customer usage'
    });
  }
});

// GET /api/customers/:external_id/invoices - Get customer invoices
router.get('/:external_id/invoices', async (req: Request, res: Response) => {
  try {
    const lagoService = LagoApiService.getInstance();
    const externalId = req.params.external_id;
    const page = parseInt(req.query.page as string) || 1;
    const perPage = Math.min(parseInt(req.query.per_page as string) || 20, 100);

    logger.debug('Getting customer invoices', { externalId, page, perPage });

    const result = await lagoService.getInvoices(externalId, page, perPage);

    res.json(result);

  } catch (error) {
    logger.error('Failed to get customer invoices', { 
      externalId: req.params.external_id,
      error: error.message 
    });

    res.status(500).json({
      error: 'Failed to get customer invoices'
    });
  }
});

export { router as customerRoutes };