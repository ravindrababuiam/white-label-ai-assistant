// Note: In a real implementation, this would be imported from the installed package
// import { MCPClient } from 'open-webui-mcp-integration';

// For this implementation, we'll create a simplified interface
interface MCPClientInterface {
  connect(auth?: any): Promise<void>;
  disconnect(): Promise<void>;
  initialize(capabilities: any): Promise<any>;
  listTools(): Promise<any[]>;
  listResources(): Promise<any[]>;
  listPrompts(): Promise<any[]>;
  callTool(name: string, args: any): Promise<any>;
  readResource(uri: string): Promise<any>;
  getPrompt(name: string, args?: any): Promise<any>;
  on(event: string, handler: Function): void;
  emit(event: string, ...args: any[]): void;
}

// Simplified MCPClient implementation for this integration
class MCPClient extends EventEmitter implements MCPClientInterface {
  constructor(
    private serverId: string,
    private endpoint: string,
    private protocol: string
  ) {
    super();
  }

  async connect(auth?: any): Promise<void> {
    // Implementation would connect to the actual MCP server
    this.emit('connected');
  }

  async disconnect(): Promise<void> {
    // Implementation would disconnect from the MCP server
    this.emit('disconnected');
  }

  async initialize(capabilities: any): Promise<any> {
    // Implementation would initialize the MCP connection
    return {
      name: 'Agency MCP Server',
      version: '1.0.0',
      capabilities: {}
    };
  }

  async listTools(): Promise<any[]> {
    // Implementation would list available tools
    return [];
  }

  async listResources(): Promise<any[]> {
    // Implementation would list available resources
    return [];
  }

  async listPrompts(): Promise<any[]> {
    // Implementation would list available prompts
    return [];
  }

  async callTool(name: string, args: any): Promise<any> {
    // Implementation would call the specified tool
    return { result: 'success' };
  }

  async readResource(uri: string): Promise<any> {
    // Implementation would read the specified resource
    return { content: 'resource content' };
  }

  async getPrompt(name: string, args?: any): Promise<any> {
    // Implementation would get the specified prompt
    return { messages: [] };
  }
}
import { EventEmitter } from 'events';

export interface AgencyMCPConfig {
  server: {
    id: string;
    name: string;
    description: string;
    endpoint: string;
    protocol: 'stdio' | 'sse' | 'websocket';
    enabled: boolean;
    autoConnect: boolean;
    timeout: number;
    retryPolicy: {
      enabled: boolean;
      maxRetries: number;
      backoffMultiplier: number;
      initialDelay: number;
    };
    healthCheck: {
      enabled: boolean;
      interval: number;
      timeout: number;
      retries: number;
    };
    tags: string[];
  };
  authentication: {
    type: 'bearer' | 'oauth2';
    token?: string;
    refreshToken?: string;
    tokenEndpoint?: string;
    clientId?: string;
    clientSecret?: string;
  };
  capabilities: {
    expectedTools: string[];
    expectedResources: string[];
    expectedPrompts: string[];
  };
  security: {
    allowedOrigins: string[];
    requiredScopes: string[];
    rateLimiting: {
      enabled: boolean;
      requestsPerMinute: number;
      burstLimit: number;
    };
  };
  monitoring: {
    metricsEndpoint?: string;
    logsEndpoint?: string;
    alertsEndpoint?: string;
    enableDetailedLogging: boolean;
    logLevel: 'DEBUG' | 'INFO' | 'WARN' | 'ERROR';
  };
}

export interface AgencyToolExecution {
  toolName: string;
  arguments: Record<string, any>;
  result?: any;
  error?: string;
  timestamp: Date;
  duration?: number;
  userId?: string;
  sessionId?: string;
}

export interface AgencyMetrics {
  totalRequests: number;
  successfulRequests: number;
  failedRequests: number;
  averageResponseTime: number;
  lastRequestTime?: Date;
  uptimePercentage: number;
  rateLimitHits: number;
  authenticationFailures: number;
}

export class AgencyMCPClient extends EventEmitter {
  private client: MCPClient;
  private config: AgencyMCPConfig;
  private isInitialized = false;
  private accessToken: string | null = null;
  private tokenExpiresAt: Date | null = null;
  private metrics: AgencyMetrics;
  private rateLimitTracker = new Map<string, number[]>();

  constructor(config: AgencyMCPConfig) {
    super();
    this.config = config;
    this.client = new MCPClient(
      config.server.id,
      this.resolveEndpoint(config.server.endpoint),
      config.server.protocol
    );
    
    this.metrics = {
      totalRequests: 0,
      successfulRequests: 0,
      failedRequests: 0,
      averageResponseTime: 0,
      uptimePercentage: 0,
      rateLimitHits: 0,
      authenticationFailures: 0
    };

    this.setupClientEventHandlers();
  }

  async initialize(): Promise<void> {
    if (this.isInitialized) {
      return;
    }

    try {
      // Authenticate first
      await this.authenticate();

      // Connect to the MCP server
      await this.client.connect(this.getAuthenticationConfig());

      // Initialize the MCP connection
      const serverInfo = await this.client.initialize({
        roots: { listChanged: true },
        sampling: {}
      });

      // Validate server capabilities
      await this.validateServerCapabilities();

      this.isInitialized = true;
      this.emit('initialized', serverInfo);

      // Start monitoring if configured
      if (this.config.monitoring.metricsEndpoint) {
        this.startMetricsReporting();
      }

    } catch (error) {
      this.emit('initialization-error', error);
      throw error;
    }
  }

  async disconnect(): Promise<void> {
    if (this.client) {
      await this.client.disconnect();
    }
    this.isInitialized = false;
    this.emit('disconnected');
  }

  async executeAgencyTool(
    toolName: string, 
    arguments_: Record<string, any>,
    context?: { userId?: string; sessionId?: string }
  ): Promise<any> {
    if (!this.isInitialized) {
      throw new Error('Agency MCP client not initialized');
    }

    // Check rate limiting
    if (!this.checkRateLimit(context?.userId || 'anonymous')) {
      this.metrics.rateLimitHits++;
      throw new Error('Rate limit exceeded');
    }

    const startTime = Date.now();
    const execution: AgencyToolExecution = {
      toolName,
      arguments: arguments_,
      timestamp: new Date(),
      userId: context?.userId,
      sessionId: context?.sessionId
    };

    try {
      // Ensure we have a valid token
      await this.ensureValidToken();

      // Execute the tool
      const result = await this.client.callTool(toolName, arguments_);
      
      execution.result = result;
      execution.duration = Date.now() - startTime;
      
      this.updateMetrics(true, execution.duration);
      this.emit('tool-executed', execution);
      
      // Log to monitoring system if configured
      if (this.config.monitoring.enableDetailedLogging) {
        await this.logExecution(execution);
      }
      
      return result;
    } catch (error) {
      execution.error = error instanceof Error ? error.message : String(error);
      execution.duration = Date.now() - startTime;
      
      this.updateMetrics(false, execution.duration);
      this.emit('tool-error', execution);
      
      // Log error to monitoring system
      if (this.config.monitoring.enableDetailedLogging) {
        await this.logExecution(execution);
      }
      
      throw error;
    }
  }

  async listAgencyTools(): Promise<any[]> {
    if (!this.isInitialized) {
      throw new Error('Agency MCP client not initialized');
    }

    await this.ensureValidToken();
    return await this.client.listTools();
  }

  async listAgencyResources(): Promise<any[]> {
    if (!this.isInitialized) {
      throw new Error('Agency MCP client not initialized');
    }

    await this.ensureValidToken();
    return await this.client.listResources();
  }

  async readAgencyResource(uri: string): Promise<any> {
    if (!this.isInitialized) {
      throw new Error('Agency MCP client not initialized');
    }

    await this.ensureValidToken();
    return await this.client.readResource(uri);
  }

  async listAgencyPrompts(): Promise<any[]> {
    if (!this.isInitialized) {
      throw new Error('Agency MCP client not initialized');
    }

    await this.ensureValidToken();
    return await this.client.listPrompts();
  }

  async getAgencyPrompt(name: string, arguments_?: Record<string, any>): Promise<any> {
    if (!this.isInitialized) {
      throw new Error('Agency MCP client not initialized');
    }

    await this.ensureValidToken();
    return await this.client.getPrompt(name, arguments_);
  }

  getMetrics(): AgencyMetrics {
    return { ...this.metrics };
  }

  getConfig(): AgencyMCPConfig {
    return { ...this.config };
  }

  private async authenticate(): Promise<void> {
    if (this.config.authentication.type === 'bearer' && this.config.authentication.token) {
      this.accessToken = this.resolveEnvironmentVariable(this.config.authentication.token);
      this.tokenExpiresAt = null; // Bearer tokens don't typically expire
    } else if (this.config.authentication.type === 'oauth2') {
      await this.performOAuth2Flow();
    } else {
      throw new Error('Invalid authentication configuration');
    }
  }

  private async performOAuth2Flow(): Promise<void> {
    if (!this.config.authentication.tokenEndpoint || 
        !this.config.authentication.clientId || 
        !this.config.authentication.clientSecret) {
      throw new Error('OAuth2 configuration incomplete');
    }

    const tokenEndpoint = this.resolveEnvironmentVariable(this.config.authentication.tokenEndpoint);
    const clientId = this.resolveEnvironmentVariable(this.config.authentication.clientId);
    const clientSecret = this.resolveEnvironmentVariable(this.config.authentication.clientSecret);

    try {
      const response = await fetch(tokenEndpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': `Basic ${btoa(`${clientId}:${clientSecret}`)}`
        },
        body: new URLSearchParams({
          grant_type: 'client_credentials',
          scope: this.config.security.requiredScopes.join(' ')
        })
      });

      if (!response.ok) {
        throw new Error(`OAuth2 token request failed: ${response.status} ${response.statusText}`);
      }

      const tokenData = await response.json();
      this.accessToken = tokenData.access_token;
      
      if (tokenData.expires_in) {
        this.tokenExpiresAt = new Date(Date.now() + (tokenData.expires_in * 1000));
      }

    } catch (error) {
      this.metrics.authenticationFailures++;
      throw new Error(`OAuth2 authentication failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
  }

  private async ensureValidToken(): Promise<void> {
    if (!this.accessToken) {
      await this.authenticate();
      return;
    }

    // Check if token is expired (with 5 minute buffer)
    if (this.tokenExpiresAt && this.tokenExpiresAt.getTime() - Date.now() < 300000) {
      await this.authenticate();
    }
  }

  private getAuthenticationConfig(): any {
    return {
      type: 'bearer',
      token: this.accessToken
    };
  }

  private async validateServerCapabilities(): Promise<void> {
    try {
      // Check if expected tools are available
      const availableTools = await this.client.listTools();
      const toolNames = availableTools.map((tool: any) => tool.name);
      
      const missingTools = this.config.capabilities.expectedTools.filter(
        tool => !toolNames.includes(tool)
      );

      if (missingTools.length > 0) {
        console.warn(`Missing expected tools: ${missingTools.join(', ')}`);
        this.emit('capability-warning', { type: 'tools', missing: missingTools });
      }

      // Check if expected resources are available
      const availableResources = await this.client.listResources();
      const resourceUris = availableResources.map((resource: any) => resource.uri);
      
      // This is a simplified check - in practice, you might want more sophisticated validation
      const missingResources = this.config.capabilities.expectedResources.filter(
        resource => !resourceUris.some(uri => uri.includes(resource))
      );

      if (missingResources.length > 0) {
        console.warn(`Missing expected resources: ${missingResources.join(', ')}`);
        this.emit('capability-warning', { type: 'resources', missing: missingResources });
      }

      // Check if expected prompts are available
      const availablePrompts = await this.client.listPrompts();
      const promptNames = availablePrompts.map((prompt: any) => prompt.name);
      
      const missingPrompts = this.config.capabilities.expectedPrompts.filter(
        prompt => !promptNames.includes(prompt)
      );

      if (missingPrompts.length > 0) {
        console.warn(`Missing expected prompts: ${missingPrompts.join(', ')}`);
        this.emit('capability-warning', { type: 'prompts', missing: missingPrompts });
      }

    } catch (error) {
      console.warn('Failed to validate server capabilities:', error);
      this.emit('capability-validation-error', error);
    }
  }

  private checkRateLimit(userId: string): boolean {
    if (!this.config.security.rateLimiting.enabled) {
      return true;
    }

    const now = Date.now();
    const windowMs = 60000; // 1 minute
    const maxRequests = this.config.security.rateLimiting.requestsPerMinute;

    if (!this.rateLimitTracker.has(userId)) {
      this.rateLimitTracker.set(userId, []);
    }

    const userRequests = this.rateLimitTracker.get(userId)!;
    
    // Remove old requests outside the window
    const validRequests = userRequests.filter(timestamp => now - timestamp < windowMs);
    
    if (validRequests.length >= maxRequests) {
      return false;
    }

    // Add current request
    validRequests.push(now);
    this.rateLimitTracker.set(userId, validRequests);
    
    return true;
  }

  private updateMetrics(success: boolean, duration: number): void {
    this.metrics.totalRequests++;
    this.metrics.lastRequestTime = new Date();

    if (success) {
      this.metrics.successfulRequests++;
    } else {
      this.metrics.failedRequests++;
    }

    // Update average response time
    const totalSuccessful = this.metrics.successfulRequests;
    if (totalSuccessful > 0) {
      this.metrics.averageResponseTime = 
        (this.metrics.averageResponseTime * (totalSuccessful - 1) + duration) / totalSuccessful;
    }

    // Calculate uptime percentage
    this.metrics.uptimePercentage = (this.metrics.successfulRequests / this.metrics.totalRequests) * 100;
  }

  private async logExecution(execution: AgencyToolExecution): Promise<void> {
    if (!this.config.monitoring.logsEndpoint) {
      return;
    }

    try {
      const logEntry = {
        timestamp: execution.timestamp.toISOString(),
        serverId: this.config.server.id,
        toolName: execution.toolName,
        userId: execution.userId,
        sessionId: execution.sessionId,
        duration: execution.duration,
        success: !execution.error,
        error: execution.error,
        level: execution.error ? 'ERROR' : 'INFO'
      };

      await fetch(this.resolveEnvironmentVariable(this.config.monitoring.logsEndpoint), {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.accessToken}`
        },
        body: JSON.stringify(logEntry)
      });
    } catch (error) {
      console.warn('Failed to log execution:', error);
    }
  }

  private startMetricsReporting(): void {
    if (!this.config.monitoring.metricsEndpoint) {
      return;
    }

    // Report metrics every 60 seconds
    setInterval(async () => {
      try {
        await fetch(this.resolveEnvironmentVariable(this.config.monitoring.metricsEndpoint!), {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${this.accessToken}`
          },
          body: JSON.stringify({
            timestamp: new Date().toISOString(),
            serverId: this.config.server.id,
            metrics: this.metrics
          })
        });
      } catch (error) {
        console.warn('Failed to report metrics:', error);
      }
    }, 60000);
  }

  private setupClientEventHandlers(): void {
    this.client.on('connected', () => {
      this.emit('connected');
    });

    this.client.on('disconnected', () => {
      this.emit('disconnected');
    });

    this.client.on('error', (error) => {
      this.emit('error', error);
    });

    this.client.on('notification', (method, params) => {
      this.emit('notification', method, params);
    });
  }

  private resolveEndpoint(endpoint: string): string {
    return this.resolveEnvironmentVariable(endpoint);
  }

  private resolveEnvironmentVariable(value: string): string {
    // Replace environment variable placeholders
    return value.replace(/\$\{([^}]+)\}/g, (match, varName) => {
      const envValue = process.env[varName];
      if (envValue === undefined) {
        throw new Error(`Environment variable ${varName} is not defined`);
      }
      return envValue;
    });
  }
}