import { EventEmitter } from 'events';
import { AgencyMCPClient, AgencyMCPConfig } from './agency-mcp-client.js';
import * as fs from 'fs/promises';
import * as path from 'path';

export interface AgencyIntegrationStatus {
  connected: boolean;
  authenticated: boolean;
  lastConnected?: Date;
  lastError?: string;
  serverInfo?: any;
  capabilities?: {
    tools: string[];
    resources: string[];
    prompts: string[];
  };
  metrics?: any;
}

export interface AgencyToolRequest {
  toolName: string;
  arguments: Record<string, any>;
  context?: {
    userId?: string;
    sessionId?: string;
    requestId?: string;
  };
}

export interface AgencyToolResponse {
  success: boolean;
  result?: any;
  error?: string;
  duration: number;
  timestamp: Date;
}

export class AgencyIntegrationManager extends EventEmitter {
  private client: AgencyMCPClient | null = null;
  private config: AgencyMCPConfig | null = null;
  private status: AgencyIntegrationStatus = {
    connected: false,
    authenticated: false
  };
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 5;
  private reconnectDelay = 5000; // 5 seconds

  constructor() {
    super();
  }

  async initialize(configPath?: string): Promise<void> {
    try {
      // Load configuration
      this.config = await this.loadConfiguration(configPath);
      
      // Create client
      this.client = new AgencyMCPClient(this.config);
      
      // Set up event handlers
      this.setupEventHandlers();
      
      // Initialize connection
      await this.connect();
      
      this.emit('initialized');
    } catch (error) {
      this.updateStatus({ lastError: error instanceof Error ? error.message : String(error) });
      this.emit('initialization-error', error);
      throw error;
    }
  }

  async connect(): Promise<void> {
    if (!this.client) {
      throw new Error('Client not initialized');
    }

    try {
      await this.client.initialize();
      
      // Load capabilities
      const capabilities = await this.loadCapabilities();
      
      this.updateStatus({
        connected: true,
        authenticated: true,
        lastConnected: new Date(),
        lastError: undefined,
        capabilities
      });
      
      this.reconnectAttempts = 0;
      this.emit('connected');
    } catch (error) {
      this.updateStatus({
        connected: false,
        authenticated: false,
        lastError: error instanceof Error ? error.message : String(error)
      });
      
      this.emit('connection-error', error);
      
      // Attempt reconnection if configured
      if (this.config?.server.retryPolicy.enabled && this.reconnectAttempts < this.maxReconnectAttempts) {
        this.scheduleReconnect();
      }
      
      throw error;
    }
  }

  async disconnect(): Promise<void> {
    if (this.client) {
      await this.client.disconnect();
    }
    
    this.updateStatus({
      connected: false,
      authenticated: false
    });
    
    this.emit('disconnected');
  }

  async executeTool(request: AgencyToolRequest): Promise<AgencyToolResponse> {
    if (!this.client || !this.status.connected) {
      throw new Error('Agency MCP client not connected');
    }

    const startTime = Date.now();
    
    try {
      const result = await this.client.executeAgencyTool(
        request.toolName,
        request.arguments,
        request.context
      );
      
      const response: AgencyToolResponse = {
        success: true,
        result,
        duration: Date.now() - startTime,
        timestamp: new Date()
      };
      
      this.emit('tool-executed', request, response);
      return response;
    } catch (error) {
      const response: AgencyToolResponse = {
        success: false,
        error: error instanceof Error ? error.message : String(error),
        duration: Date.now() - startTime,
        timestamp: new Date()
      };
      
      this.emit('tool-error', request, response);
      return response;
    }
  }

  async listAvailableTools(): Promise<any[]> {
    if (!this.client || !this.status.connected) {
      throw new Error('Agency MCP client not connected');
    }

    return await this.client.listAgencyTools();
  }

  async listAvailableResources(): Promise<any[]> {
    if (!this.client || !this.status.connected) {
      throw new Error('Agency MCP client not connected');
    }

    return await this.client.listAgencyResources();
  }

  async readResource(uri: string): Promise<any> {
    if (!this.client || !this.status.connected) {
      throw new Error('Agency MCP client not connected');
    }

    return await this.client.readAgencyResource(uri);
  }

  async listAvailablePrompts(): Promise<any[]> {
    if (!this.client || !this.status.connected) {
      throw new Error('Agency MCP client not connected');
    }

    return await this.client.listAgencyPrompts();
  }

  async getPrompt(name: string, arguments_?: Record<string, any>): Promise<any> {
    if (!this.client || !this.status.connected) {
      throw new Error('Agency MCP client not connected');
    }

    return await this.client.getAgencyPrompt(name, arguments_);
  }

  getStatus(): AgencyIntegrationStatus {
    return { ...this.status };
  }

  getConfig(): AgencyMCPConfig | null {
    return this.config ? { ...this.config } : null;
  }

  getMetrics(): any {
    if (!this.client) {
      return null;
    }
    return this.client.getMetrics();
  }

  async healthCheck(): Promise<boolean> {
    if (!this.client || !this.status.connected) {
      return false;
    }

    try {
      // Perform a simple tool list operation as health check
      await this.client.listAgencyTools();
      return true;
    } catch (error) {
      console.warn('Health check failed:', error);
      return false;
    }
  }

  async validateConfiguration(configPath?: string): Promise<{ valid: boolean; errors: string[] }> {
    const errors: string[] = [];
    
    try {
      const config = await this.loadConfiguration(configPath);
      
      // Validate server configuration
      if (!config.server.id) {
        errors.push('Server ID is required');
      }
      
      if (!config.server.endpoint) {
        errors.push('Server endpoint is required');
      }
      
      // Validate authentication configuration
      if (config.authentication.type === 'bearer' && !config.authentication.token) {
        errors.push('Bearer token is required for bearer authentication');
      }
      
      if (config.authentication.type === 'oauth2') {
        if (!config.authentication.tokenEndpoint) {
          errors.push('Token endpoint is required for OAuth2 authentication');
        }
        if (!config.authentication.clientId) {
          errors.push('Client ID is required for OAuth2 authentication');
        }
        if (!config.authentication.clientSecret) {
          errors.push('Client secret is required for OAuth2 authentication');
        }
      }
      
      // Validate environment variables
      const envVars = this.extractEnvironmentVariables(JSON.stringify(config));
      for (const envVar of envVars) {
        if (!process.env[envVar]) {
          errors.push(`Environment variable ${envVar} is not defined`);
        }
      }
      
      return { valid: errors.length === 0, errors };
    } catch (error) {
      errors.push(`Configuration validation failed: ${error instanceof Error ? error.message : String(error)}`);
      return { valid: false, errors };
    }
  }

  private async loadConfiguration(configPath?: string): Promise<AgencyMCPConfig> {
    const defaultConfigPath = path.join(__dirname, '../config/agency-server-config.json');
    const actualConfigPath = configPath || defaultConfigPath;
    
    try {
      const configContent = await fs.readFile(actualConfigPath, 'utf-8');
      const config = JSON.parse(configContent) as AgencyMCPConfig;
      
      // Validate required fields
      if (!config.server || !config.authentication) {
        throw new Error('Invalid configuration: missing required sections');
      }
      
      return config;
    } catch (error) {
      throw new Error(`Failed to load configuration from ${actualConfigPath}: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  private async loadCapabilities(): Promise<{ tools: string[]; resources: string[]; prompts: string[] }> {
    if (!this.client) {
      throw new Error('Client not initialized');
    }

    try {
      const [tools, resources, prompts] = await Promise.all([
        this.client.listAgencyTools(),
        this.client.listAgencyResources(),
        this.client.listAgencyPrompts()
      ]);

      return {
        tools: tools.map((tool: any) => tool.name),
        resources: resources.map((resource: any) => resource.uri),
        prompts: prompts.map((prompt: any) => prompt.name)
      };
    } catch (error) {
      console.warn('Failed to load capabilities:', error);
      return { tools: [], resources: [], prompts: [] };
    }
  }

  private setupEventHandlers(): void {
    if (!this.client) {
      return;
    }

    this.client.on('connected', () => {
      this.updateStatus({ connected: true });
      this.emit('connected');
    });

    this.client.on('disconnected', () => {
      this.updateStatus({ connected: false, authenticated: false });
      this.emit('disconnected');
    });

    this.client.on('error', (error) => {
      this.updateStatus({ 
        connected: false, 
        authenticated: false,
        lastError: error instanceof Error ? error.message : String(error)
      });
      this.emit('error', error);
    });

    this.client.on('tool-executed', (execution) => {
      this.emit('tool-executed', execution);
    });

    this.client.on('tool-error', (execution) => {
      this.emit('tool-error', execution);
    });

    this.client.on('capability-warning', (warning) => {
      this.emit('capability-warning', warning);
    });

    this.client.on('capability-validation-error', (error) => {
      this.emit('capability-validation-error', error);
    });
  }

  private updateStatus(updates: Partial<AgencyIntegrationStatus>): void {
    this.status = { ...this.status, ...updates };
    this.emit('status-updated', this.status);
  }

  private scheduleReconnect(): void {
    this.reconnectAttempts++;
    
    const delay = this.reconnectDelay * Math.pow(
      this.config?.server.retryPolicy.backoffMultiplier || 2,
      this.reconnectAttempts - 1
    );
    
    setTimeout(async () => {
      try {
        await this.connect();
      } catch (error) {
        console.warn(`Reconnection attempt ${this.reconnectAttempts} failed:`, error);
      }
    }, delay);
  }

  private extractEnvironmentVariables(text: string): string[] {
    const envVarPattern = /\$\{([^}]+)\}/g;
    const envVars: string[] = [];
    let match;
    
    while ((match = envVarPattern.exec(text)) !== null) {
      if (!envVars.includes(match[1])) {
        envVars.push(match[1]);
      }
    }
    
    return envVars;
  }
}