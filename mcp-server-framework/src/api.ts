import express from 'express';
import { body, param, query, validationResult } from 'express-validator';
import { MCPServerRegistry, ListServersOptions } from './registry.js';
import { MCPServerConfig } from './types.js';

export class MCPServerAPI {
  private app: express.Application;
  private registry: MCPServerRegistry;

  constructor(registry: MCPServerRegistry) {
    this.app = express();
    this.registry = registry;
    this.setupMiddleware();
    this.setupRoutes();
  }

  private setupMiddleware(): void {
    this.app.use(express.json({ limit: '10mb' }));
    this.app.use(express.urlencoded({ extended: true }));
    
    // CORS middleware
    this.app.use((req, res, next) => {
      res.header('Access-Control-Allow-Origin', '*');
      res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
      res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization');
      
      if (req.method === 'OPTIONS') {
        res.sendStatus(200);
      } else {
        next();
      }
    });

    // Error handling middleware
    this.app.use((error: any, req: express.Request, res: express.Response, next: express.NextFunction) => {
      console.error('API Error:', error);
      res.status(500).json({
        error: 'Internal server error',
        message: error.message
      });
    });
  }

  private setupRoutes(): void {
    // Health check endpoint
    this.app.get('/health', (req: express.Request, res: express.Response) => {
      res.json({ status: 'healthy', timestamp: new Date().toISOString() });
    });

    // List all servers
    this.app.get('/servers', 
      [
        query('enabled').optional().isBoolean(),
        query('protocol').optional().isIn(['stdio', 'sse', 'websocket']),
        query('tags').optional().isString(),
        query('sortBy').optional().isIn(['name', 'id', 'registeredAt', 'protocol']),
        query('sortOrder').optional().isIn(['asc', 'desc']),
        query('page').optional().isInt({ min: 1 }),
        query('limit').optional().isInt({ min: 1, max: 100 })
      ],
      this.handleValidationErrors,
      (req: express.Request, res: express.Response) => {
        try {
          const options: ListServersOptions = {};
          
          if (req.query.enabled !== undefined) {
            options.enabled = req.query.enabled === 'true';
          }
          
          if (req.query.protocol) {
            options.protocol = req.query.protocol as any;
          }
          
          if (req.query.tags) {
            options.tags = (req.query.tags as string).split(',').map(tag => tag.trim());
          }
          
          if (req.query.sortBy) {
            options.sortBy = req.query.sortBy as any;
          }
          
          if (req.query.sortOrder) {
            options.sortOrder = req.query.sortOrder as any;
          }
          
          if (req.query.page) {
            options.page = parseInt(req.query.page as string);
          }
          
          if (req.query.limit) {
            options.limit = parseInt(req.query.limit as string);
          }

          const result = this.registry.listServers(options);
          res.json(result);
        } catch (error) {
          res.status(500).json({ error: 'Failed to list servers' });
        }
      }
    );

    // Get specific server
    this.app.get('/servers/:id',
      [param('id').isString().notEmpty()],
      this.handleValidationErrors,
      (req: express.Request, res: express.Response): void => {
        try {
          const serverId = req.params.id;
          if (!serverId) {
            res.status(400).json({ error: 'Server ID is required' });
            return;
          }
          
          const server = this.registry.getServer(serverId);
          if (!server) {
            res.status(404).json({ error: 'Server not found' });
            return;
          }
          res.json(server);
        } catch (error) {
          res.status(500).json({ error: 'Failed to get server' });
        }
      }
    );

    // Register new server
    this.app.post('/servers',
      [
        body('id').isString().notEmpty().matches(/^[a-zA-Z0-9-_]+$/),
        body('name').isString().notEmpty(),
        body('endpoint').isURL(),
        body('protocol').optional().isIn(['stdio', 'sse', 'websocket']),
        body('enabled').optional().isBoolean(),
        body('registeredBy').isString().notEmpty()
      ],
      this.handleValidationErrors,
      async (req: express.Request, res: express.Response): Promise<void> => {
        try {
          const { registeredBy, version, ...config } = req.body;
          const result = await this.registry.registerServer(config as MCPServerConfig, registeredBy, version);
          
          if (!result.valid) {
            res.status(400).json({ 
              error: 'Validation failed', 
              details: result.errors 
            });
            return;
          }
          
          res.status(201).json({ 
            message: 'Server registered successfully',
            serverId: config.id 
          });
        } catch (error) {
          res.status(500).json({ error: 'Failed to register server' });
        }
      }
    );

    // Update server
    this.app.put('/servers/:id',
      [
        param('id').isString().notEmpty(),
        body('id').isString().notEmpty().matches(/^[a-zA-Z0-9-_]+$/),
        body('name').isString().notEmpty(),
        body('endpoint').isURL(),
        body('protocol').optional().isIn(['stdio', 'sse', 'websocket']),
        body('enabled').optional().isBoolean(),
        body('updatedBy').isString().notEmpty()
      ],
      this.handleValidationErrors,
      async (req: express.Request, res: express.Response): Promise<void> => {
        try {
          const serverId = req.params.id;
          if (!serverId) {
            res.status(400).json({ error: 'Server ID is required' });
            return;
          }
          
          const { updatedBy, ...config } = req.body;
          const result = await this.registry.updateServer(serverId, config as MCPServerConfig, updatedBy);
          
          if (!result.valid) {
            res.status(400).json({ 
              error: 'Validation failed', 
              details: result.errors 
            });
            return;
          }
          
          res.json({ 
            message: 'Server updated successfully',
            serverId: serverId 
          });
        } catch (error) {
          res.status(500).json({ error: 'Failed to update server' });
        }
      }
    );

    // Delete server
    this.app.delete('/servers/:id',
      [param('id').isString().notEmpty()],
      this.handleValidationErrors,
      async (req: express.Request, res: express.Response): Promise<void> => {
        try {
          const serverId = req.params.id;
          if (!serverId) {
            res.status(400).json({ error: 'Server ID is required' });
            return;
          }
          
          const success = await this.registry.unregisterServer(serverId);
          
          if (!success) {
            res.status(404).json({ error: 'Server not found' });
            return;
          }
          
          res.json({ 
            message: 'Server unregistered successfully',
            serverId: serverId 
          });
        } catch (error) {
          res.status(500).json({ error: 'Failed to unregister server' });
        }
      }
    );

    // Get server health
    this.app.get('/servers/:id/health',
      [param('id').isString().notEmpty()],
      this.handleValidationErrors,
      (req: express.Request, res: express.Response): void => {
        try {
          const serverId = req.params.id;
          if (!serverId) {
            res.status(400).json({ error: 'Server ID is required' });
            return;
          }
          
          const health = this.registry.getServerHealth(serverId);
          if (!health) {
            res.status(404).json({ error: 'Server not found' });
            return;
          }
          res.json(health);
        } catch (error) {
          res.status(500).json({ error: 'Failed to get server health' });
        }
      }
    );

    // Get all servers health
    this.app.get('/servers/health/all', (req: express.Request, res: express.Response) => {
      try {
        const healthMap = this.registry.getAllServerHealth();
        const healthArray = Array.from(healthMap.entries()).map(([id, health]) => ({
          serverId: id,
          ...health
        }));
        res.json({ servers: healthArray });
      } catch (error) {
        res.status(500).json({ error: 'Failed to get servers health' });
      }
    });

    // Perform health check
    this.app.post('/servers/:id/health-check',
      [param('id').isString().notEmpty()],
      this.handleValidationErrors,
      async (req: express.Request, res: express.Response): Promise<void> => {
        try {
          const serverId = req.params.id;
          if (!serverId) {
            res.status(400).json({ error: 'Server ID is required' });
            return;
          }
          
          const success = await this.registry.performHealthCheck(serverId);
          res.json({ 
            serverId: serverId,
            healthy: success,
            timestamp: new Date().toISOString()
          });
        } catch (error) {
          res.status(500).json({ error: 'Failed to perform health check' });
        }
      }
    );

    // Enable server
    this.app.post('/servers/:id/enable',
      [param('id').isString().notEmpty()],
      this.handleValidationErrors,
      (req: express.Request, res: express.Response): void => {
        try {
          const serverId = req.params.id;
          if (!serverId) {
            res.status(400).json({ error: 'Server ID is required' });
            return;
          }
          
          const success = this.registry.enableServer(serverId);
          
          if (!success) {
            res.status(404).json({ error: 'Server not found' });
            return;
          }
          
          res.json({ 
            message: 'Server enabled successfully',
            serverId: serverId 
          });
        } catch (error) {
          res.status(500).json({ error: 'Failed to enable server' });
        }
      }
    );

    // Disable server
    this.app.post('/servers/:id/disable',
      [param('id').isString().notEmpty()],
      this.handleValidationErrors,
      (req: express.Request, res: express.Response): void => {
        try {
          const serverId = req.params.id;
          if (!serverId) {
            res.status(400).json({ error: 'Server ID is required' });
            return;
          }
          
          const success = this.registry.disableServer(serverId);
          
          if (!success) {
            res.status(404).json({ error: 'Server not found' });
            return;
          }
          
          res.json({ 
            message: 'Server disabled successfully',
            serverId: serverId 
          });
        } catch (error) {
          res.status(500).json({ error: 'Failed to disable server' });
        }
      }
    );

    // Validate configuration
    this.app.post('/validate',
      [body('servers').isArray()],
      this.handleValidationErrors,
      (req: express.Request, res: express.Response) => {
        try {
          const result = this.registry.validateConfiguration(req.body.servers);
          res.json(result);
        } catch (error) {
          res.status(500).json({ error: 'Failed to validate configuration' });
        }
      }
    );
  }

  private handleValidationErrors = (req: express.Request, res: express.Response, next: express.NextFunction): void => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      res.status(400).json({
        error: 'Validation failed',
        details: errors.array()
      });
      return;
    }
    next();
  };

  getApp(): express.Application {
    return this.app;
  }

  async start(port: number = 3000): Promise<void> {
    return new Promise((resolve) => {
      this.app.listen(port, () => {
        console.log(`MCP Server API listening on port ${port}`);
        resolve();
      });
    });
  }
}