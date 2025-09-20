import { MCPServerRegistry, ListServersOptions } from './registry.js';
import { MCPServerAPI } from './api.js';

export { MCPServerRegistry, ListServersOptions } from './registry.js';
export { MCPServerAPI } from './api.js';
export { MCPHealthMonitor, HealthCheckResult } from './health-monitor.js';
export { MCPConfigValidator, ValidationResult, ValidationError } from './config-validator.js';
export {
  MCPServerConfig,
  Authentication,
  HealthCheckConfig,
  RetryPolicy,
  MCPServerStatus,
  MCPServerMetrics,
  MCPServerRegistration,
  MCPServerListResponse,
  MCPServerHealthResponse
} from './types.js';

// Main framework class that combines all components
export class MCPServerFramework {
  private registry: MCPServerRegistry;
  private api: MCPServerAPI;

  constructor() {
    this.registry = new MCPServerRegistry();
    this.api = new MCPServerAPI(this.registry);
  }

  async start(port: number = 3000): Promise<void> {
    await this.registry.start();
    await this.api.start(port);
    console.log(`MCP Server Framework started on port ${port}`);
  }

  async stop(): Promise<void> {
    await this.registry.stop();
    console.log('MCP Server Framework stopped');
  }

  getRegistry(): MCPServerRegistry {
    return this.registry;
  }

  getAPI(): MCPServerAPI {
    return this.api;
  }
}