import { EventEmitter } from 'events';
import { 
  MCPServerConfig, 
  MCPServerRegistration, 
  MCPServerListResponse,
  MCPServerHealthResponse,
  MCPServerStatus,
  MCPServerMetrics
} from './types.js';
import { MCPConfigValidator, ValidationResult } from './config-validator.js';
import { MCPHealthMonitor } from './health-monitor.js';

export class MCPServerRegistry extends EventEmitter {
  private servers = new Map<string, MCPServerRegistration>();
  private validator: MCPConfigValidator;
  private healthMonitor: MCPHealthMonitor;

  constructor() {
    super();
    this.validator = new MCPConfigValidator();
    this.healthMonitor = new MCPHealthMonitor();

    // Forward health monitor events
    this.healthMonitor.on('status:changed', (serverId, newStatus, oldStatus) => {
      this.emit('server:status:changed', serverId, newStatus, oldStatus);
    });

    this.healthMonitor.on('health:checked', (serverId, result) => {
      this.emit('server:health:checked', serverId, result);
    });
  }

  async start(): Promise<void> {
    this.healthMonitor.start();
    this.emit('registry:started');
  }

  async stop(): Promise<void> {
    this.healthMonitor.stop();
    this.emit('registry:stopped');
  }

  async registerServer(
    config: MCPServerConfig, 
    registeredBy: string,
    version?: string
  ): Promise<ValidationResult> {
    // Validate configuration
    const validationResult = this.validator.validateServerConfig(config);
    if (!validationResult.valid) {
      return validationResult;
    }

    // Check if server already exists
    if (this.servers.has(config.id)) {
      return {
        valid: false,
        errors: [{
          field: 'id',
          message: `Server with ID '${config.id}' already exists`,
          value: config.id
        }]
      };
    }

    // Create registration
    const registration: MCPServerRegistration = {
      config,
      registeredAt: new Date(),
      registeredBy,
      ...(version !== undefined && { version })
    };

    // Store registration
    this.servers.set(config.id, registration);

    // Add to health monitor
    this.healthMonitor.addServer(config);

    this.emit('server:registered', config.id, registration);

    return { valid: true, errors: [] };
  }

  async updateServer(
    serverId: string,
    config: MCPServerConfig,
    updatedBy: string
  ): Promise<ValidationResult> {
    // Validate configuration
    const validationResult = this.validator.validateServerConfig(config);
    if (!validationResult.valid) {
      return validationResult;
    }

    // Check if server exists
    const existingRegistration = this.servers.get(serverId);
    if (!existingRegistration) {
      return {
        valid: false,
        errors: [{
          field: 'id',
          message: `Server with ID '${serverId}' not found`,
          value: serverId
        }]
      };
    }

    // Ensure ID consistency
    if (config.id !== serverId) {
      return {
        valid: false,
        errors: [{
          field: 'id',
          message: 'Server ID cannot be changed during update',
          value: config.id
        }]
      };
    }

    // Update registration
    const updatedRegistration: MCPServerRegistration = {
      ...existingRegistration,
      config,
      registeredBy: updatedBy, // Track who made the update
    };

    this.servers.set(serverId, updatedRegistration);

    // Update health monitor
    this.healthMonitor.updateServer(config);

    this.emit('server:updated', serverId, updatedRegistration);

    return { valid: true, errors: [] };
  }

  async unregisterServer(serverId: string): Promise<boolean> {
    const registration = this.servers.get(serverId);
    if (!registration) {
      return false;
    }

    // Remove from registry
    this.servers.delete(serverId);

    // Remove from health monitor
    this.healthMonitor.removeServer(serverId);

    this.emit('server:unregistered', serverId, registration);

    return true;
  }

  getServer(serverId: string): MCPServerRegistration | undefined {
    return this.servers.get(serverId);
  }

  listServers(options?: ListServersOptions): MCPServerListResponse {
    let serverList = Array.from(this.servers.values());

    // Apply filters
    if (options?.enabled !== undefined) {
      serverList = serverList.filter(reg => reg.config.enabled === options.enabled);
    }

    if (options?.tags && options.tags.length > 0) {
      serverList = serverList.filter(reg => 
        options.tags!.some(tag => reg.config.tags?.includes(tag))
      );
    }

    if (options?.protocol) {
      serverList = serverList.filter(reg => 
        (reg.config.protocol || 'stdio') === options.protocol
      );
    }

    // Apply sorting
    if (options?.sortBy) {
      serverList.sort((a, b) => {
        const aValue = this.getSortValue(a, options.sortBy!);
        const bValue = this.getSortValue(b, options.sortBy!);
        
        if (options.sortOrder === 'desc') {
          return bValue.localeCompare(aValue);
        }
        return aValue.localeCompare(bValue);
      });
    }

    // Apply pagination
    const total = serverList.length;
    if (options?.page && options?.limit) {
      const startIndex = (options.page - 1) * options.limit;
      serverList = serverList.slice(startIndex, startIndex + options.limit);
    }

    return {
      servers: serverList,
      total,
      ...(options?.page !== undefined && { page: options.page }),
      ...(options?.limit !== undefined && { limit: options.limit })
    };
  }

  getServerHealth(serverId: string): MCPServerHealthResponse | undefined {
    const registration = this.servers.get(serverId);
    if (!registration) {
      return undefined;
    }

    const status = this.healthMonitor.getServerStatus(serverId);
    const metrics = this.healthMonitor.getServerMetrics(serverId);

    if (!status || !metrics) {
      return undefined;
    }

    return {
      server: registration.config,
      status,
      metrics
    };
  }

  getAllServerHealth(): Map<string, MCPServerHealthResponse> {
    const healthMap = new Map<string, MCPServerHealthResponse>();

    for (const [serverId, registration] of this.servers) {
      const health = this.getServerHealth(serverId);
      if (health) {
        healthMap.set(serverId, health);
      }
    }

    return healthMap;
  }

  async performHealthCheck(serverId: string): Promise<boolean> {
    const registration = this.servers.get(serverId);
    if (!registration) {
      return false;
    }

    try {
      const result = await this.healthMonitor.performHealthCheck(registration.config);
      return result.success;
    } catch (error) {
      return false;
    }
  }

  enableServer(serverId: string): boolean {
    const registration = this.servers.get(serverId);
    if (!registration) {
      return false;
    }

    registration.config.enabled = true;
    this.healthMonitor.updateServer(registration.config);
    
    this.emit('server:enabled', serverId);
    return true;
  }

  disableServer(serverId: string): boolean {
    const registration = this.servers.get(serverId);
    if (!registration) {
      return false;
    }

    registration.config.enabled = false;
    this.healthMonitor.updateServer(registration.config);
    
    this.emit('server:disabled', serverId);
    return true;
  }

  validateConfiguration(configs: MCPServerConfig[]): ValidationResult {
    return this.validator.validateServerList(configs);
  }

  private getSortValue(registration: MCPServerRegistration, sortBy: string): string {
    switch (sortBy) {
      case 'name':
        return registration.config.name;
      case 'id':
        return registration.config.id;
      case 'registeredAt':
        return registration.registeredAt.toISOString();
      case 'protocol':
        return registration.config.protocol || 'stdio';
      default:
        return registration.config.name;
    }
  }
}

export interface ListServersOptions {
  enabled?: boolean;
  tags?: string[];
  protocol?: 'stdio' | 'sse' | 'websocket';
  sortBy?: 'name' | 'id' | 'registeredAt' | 'protocol';
  sortOrder?: 'asc' | 'desc';
  page?: number;
  limit?: number;
}