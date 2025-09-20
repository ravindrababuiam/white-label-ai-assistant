import { EventEmitter } from 'events';
import { MCPServerConfig, MCPServerStatus, MCPServerMetrics, HealthCheckConfig } from './types.js';

export class MCPHealthMonitor extends EventEmitter {
  private healthChecks = new Map<string, NodeJS.Timeout>();
  private serverStatus = new Map<string, MCPServerStatus>();
  private serverMetrics = new Map<string, MCPServerMetrics>();
  private isRunning = false;

  constructor() {
    super();
  }

  start(): void {
    this.isRunning = true;
    this.emit('monitor:started');
  }

  stop(): void {
    this.isRunning = false;
    
    // Clear all health check intervals
    for (const [serverId, interval] of this.healthChecks) {
      clearInterval(interval);
    }
    this.healthChecks.clear();
    
    this.emit('monitor:stopped');
  }

  addServer(config: MCPServerConfig): void {
    if (!this.isRunning) {
      throw new Error('Health monitor is not running');
    }

    // Initialize status and metrics
    this.serverStatus.set(config.id, {
      id: config.id,
      status: 'unknown',
      lastCheck: new Date(),
    });

    this.serverMetrics.set(config.id, {
      id: config.id,
      totalRequests: 0,
      successfulRequests: 0,
      failedRequests: 0,
      averageResponseTime: 0,
      uptimePercentage: 0,
    });

    // Start health checks if enabled
    if (config.enabled !== false && config.healthCheck?.enabled !== false) {
      this.startHealthCheck(config);
    } else {
      this.updateServerStatus(config.id, 'disabled');
    }

    this.emit('server:added', config.id);
  }

  removeServer(serverId: string): void {
    // Stop health check
    const interval = this.healthChecks.get(serverId);
    if (interval) {
      clearInterval(interval);
      this.healthChecks.delete(serverId);
    }

    // Remove status and metrics
    this.serverStatus.delete(serverId);
    this.serverMetrics.delete(serverId);

    this.emit('server:removed', serverId);
  }

  updateServer(config: MCPServerConfig): void {
    // Remove existing server
    this.removeServer(config.id);
    
    // Add updated server
    this.addServer(config);
    
    this.emit('server:updated', config.id);
  }

  getServerStatus(serverId: string): MCPServerStatus | undefined {
    return this.serverStatus.get(serverId);
  }

  getServerMetrics(serverId: string): MCPServerMetrics | undefined {
    return this.serverMetrics.get(serverId);
  }

  getAllServerStatus(): Map<string, MCPServerStatus> {
    return new Map(this.serverStatus);
  }

  getAllServerMetrics(): Map<string, MCPServerMetrics> {
    return new Map(this.serverMetrics);
  }

  async performHealthCheck(config: MCPServerConfig): Promise<HealthCheckResult> {
    const startTime = Date.now();
    
    try {
      const result = await this.executeHealthCheck(config);
      const responseTime = Date.now() - startTime;
      
      // Update metrics
      this.updateMetrics(config.id, true, responseTime);
      
      return {
        success: true,
        responseTime,
        timestamp: new Date(),
      };
    } catch (error) {
      const responseTime = Date.now() - startTime;
      
      // Update metrics
      this.updateMetrics(config.id, false, responseTime);
      
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error',
        responseTime,
        timestamp: new Date(),
      };
    }
  }

  private startHealthCheck(config: MCPServerConfig): void {
    const healthConfig = config.healthCheck || {};
    const interval = healthConfig.interval || 30000; // Default 30 seconds
    
    // Perform initial health check
    this.performHealthCheck(config).then(result => {
      this.handleHealthCheckResult(config.id, result, healthConfig);
    });

    // Set up recurring health checks
    const intervalId = setInterval(async () => {
      const result = await this.performHealthCheck(config);
      this.handleHealthCheckResult(config.id, result, healthConfig);
    }, interval);

    this.healthChecks.set(config.id, intervalId);
  }

  private async executeHealthCheck(config: MCPServerConfig): Promise<void> {
    const timeout = config.healthCheck?.timeout || 5000;
    
    switch (config.protocol) {
      case 'stdio':
        return this.checkStdioServer(config, timeout);
      case 'sse':
      case 'websocket':
        return this.checkHttpServer(config, timeout);
      default:
        return this.checkHttpServer(config, timeout);
    }
  }

  private async checkStdioServer(config: MCPServerConfig, timeout: number): Promise<void> {
    // For stdio servers, we can check if the command is executable
    // This is a simplified check - in a real implementation, you might
    // want to actually spawn the process and test MCP communication
    
    if (!config.command) {
      throw new Error('No command specified for stdio server');
    }

    // Simulate a basic command check
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        reject(new Error('Health check timeout'));
      }, timeout);

      // In a real implementation, you would spawn the process and test MCP protocol
      // For now, we'll just resolve after a short delay
      setTimeout(() => {
        clearTimeout(timer);
        resolve();
      }, 100);
    });
  }

  private async checkHttpServer(config: MCPServerConfig, timeout: number): Promise<void> {
    // For HTTP-based servers, perform a simple HTTP request
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeout);

    try {
      const response = await fetch(config.endpoint, {
        method: 'GET',
        signal: controller.signal,
        headers: this.buildAuthHeaders(config.authentication),
      });

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }
    } finally {
      clearTimeout(timeoutId);
    }
  }

  private buildAuthHeaders(auth?: any): Record<string, string> {
    const headers: Record<string, string> = {};

    if (!auth || auth.type === 'none') {
      return headers;
    }

    switch (auth.type) {
      case 'bearer':
        if (auth.token) {
          headers['Authorization'] = `Bearer ${auth.token}`;
        }
        break;
      case 'api-key':
        if (auth.token) {
          const headerName = auth.header || 'X-API-Key';
          headers[headerName] = auth.token;
        }
        break;
      case 'basic':
        if (auth.username && auth.password) {
          const credentials = Buffer.from(`${auth.username}:${auth.password}`).toString('base64');
          headers['Authorization'] = `Basic ${credentials}`;
        }
        break;
    }

    return headers;
  }

  private handleHealthCheckResult(
    serverId: string,
    result: HealthCheckResult,
    healthConfig: HealthCheckConfig
  ): void {
    const currentStatus = this.serverStatus.get(serverId);
    if (!currentStatus) return;

    const newStatus: MCPServerStatus = {
      ...currentStatus,
      lastCheck: result.timestamp,
      responseTime: result.responseTime,
    };

    if (result.success) {
      newStatus.status = 'healthy';
      delete newStatus.lastError;
    } else {
      newStatus.status = 'unhealthy';
      newStatus.lastError = result.error;
    }

    this.serverStatus.set(serverId, newStatus);

    // Emit status change event
    if (currentStatus.status !== newStatus.status) {
      this.emit('status:changed', serverId, newStatus.status, currentStatus.status);
    }

    this.emit('health:checked', serverId, result);
  }

  private updateMetrics(serverId: string, success: boolean, responseTime: number): void {
    const metrics = this.serverMetrics.get(serverId);
    if (!metrics) return;

    metrics.totalRequests++;
    metrics.lastRequestTime = new Date();

    if (success) {
      metrics.successfulRequests++;
    } else {
      metrics.failedRequests++;
    }

    // Update average response time (simple moving average)
    const totalSuccessful = metrics.successfulRequests;
    if (totalSuccessful > 0) {
      metrics.averageResponseTime = 
        (metrics.averageResponseTime * (totalSuccessful - 1) + responseTime) / totalSuccessful;
    }

    // Calculate uptime percentage
    metrics.uptimePercentage = (metrics.successfulRequests / metrics.totalRequests) * 100;

    this.serverMetrics.set(serverId, metrics);
  }

  private updateServerStatus(serverId: string, status: MCPServerStatus['status']): void {
    const currentStatus = this.serverStatus.get(serverId);
    if (currentStatus) {
      currentStatus.status = status;
      currentStatus.lastCheck = new Date();
      this.serverStatus.set(serverId, currentStatus);
    }
  }
}

export interface HealthCheckResult {
  success: boolean;
  error?: string;
  responseTime: number;
  timestamp: Date;
}