import { EventEmitter } from 'events';
import { MCPClient, MCPTool, MCPResource, MCPPrompt, MCPServerInfo } from './mcp-client.js';

export interface MCPServerConfig {
  id: string;
  name: string;
  endpoint: string;
  protocol: 'stdio' | 'sse' | 'websocket';
  authentication?: any;
  enabled: boolean;
  autoConnect?: boolean;
}

export interface MCPServerStatus {
  id: string;
  connected: boolean;
  lastConnected?: Date;
  lastError?: string;
  serverInfo?: MCPServerInfo;
}

export interface MCPToolExecution {
  serverId: string;
  toolName: string;
  arguments: Record<string, any>;
  result?: any;
  error?: string;
  timestamp: Date;
  duration?: number;
}

export class MCPManager extends EventEmitter {
  private clients = new Map<string, MCPClient>();
  private serverConfigs = new Map<string, MCPServerConfig>();
  private serverStatus = new Map<string, MCPServerStatus>();
  private toolExecutionHistory: MCPToolExecution[] = [];
  private maxHistorySize = 1000;

  constructor() {
    super();
  }

  async addServer(config: MCPServerConfig): Promise<void> {
    if (this.clients.has(config.id)) {
      throw new Error(`Server ${config.id} already exists`);
    }

    this.serverConfigs.set(config.id, config);
    this.serverStatus.set(config.id, {
      id: config.id,
      connected: false
    });

    const client = new MCPClient(config.id, config.endpoint, config.protocol);
    
    // Set up event handlers
    client.on('connected', () => {
      this.updateServerStatus(config.id, { connected: true, lastConnected: new Date() });
      this.emit('server:connected', config.id);
    });

    client.on('disconnected', () => {
      this.updateServerStatus(config.id, { connected: false });
      this.emit('server:disconnected', config.id);
    });

    client.on('error', (error) => {
      this.updateServerStatus(config.id, { 
        connected: false, 
        lastError: error.message 
      });
      this.emit('server:error', config.id, error);
    });

    client.on('notification', (method, params) => {
      this.emit('server:notification', config.id, method, params);
    });

    this.clients.set(config.id, client);

    if (config.enabled && config.autoConnect !== false) {
      try {
        await this.connectServer(config.id);
      } catch (error) {
        console.warn(`Failed to auto-connect to server ${config.id}:`, error);
      }
    }

    this.emit('server:added', config.id);
  }

  async removeServer(serverId: string): Promise<void> {
    const client = this.clients.get(serverId);
    if (client) {
      await client.disconnect();
      this.clients.delete(serverId);
    }

    this.serverConfigs.delete(serverId);
    this.serverStatus.delete(serverId);

    this.emit('server:removed', serverId);
  }

  async connectServer(serverId: string): Promise<void> {
    const client = this.clients.get(serverId);
    const config = this.serverConfigs.get(serverId);

    if (!client || !config) {
      throw new Error(`Server ${serverId} not found`);
    }

    if (!config.enabled) {
      throw new Error(`Server ${serverId} is disabled`);
    }

    await client.connect(config.authentication);

    // Initialize the connection
    const serverInfo = await client.initialize({
      roots: { listChanged: true },
      sampling: {}
    });

    this.updateServerStatus(serverId, { 
      connected: true, 
      lastConnected: new Date(),
      serverInfo 
    });
  }

  async disconnectServer(serverId: string): Promise<void> {
    const client = this.clients.get(serverId);
    if (!client) {
      throw new Error(`Server ${serverId} not found`);
    }

    await client.disconnect();
  }

  async enableServer(serverId: string): Promise<void> {
    const config = this.serverConfigs.get(serverId);
    if (!config) {
      throw new Error(`Server ${serverId} not found`);
    }

    config.enabled = true;
    this.emit('server:enabled', serverId);
  }

  async disableServer(serverId: string): Promise<void> {
    const config = this.serverConfigs.get(serverId);
    if (!config) {
      throw new Error(`Server ${serverId} not found`);
    }

    config.enabled = false;
    await this.disconnectServer(serverId);
    this.emit('server:disabled', serverId);
  }

  async listAvailableTools(): Promise<Array<MCPTool & { serverId: string }>> {
    const allTools: Array<MCPTool & { serverId: string }> = [];

    for (const [serverId, client] of this.clients) {
      const status = this.serverStatus.get(serverId);
      if (status?.connected) {
        try {
          const tools = await client.listTools();
          for (const tool of tools) {
            allTools.push({ ...tool, serverId });
          }
        } catch (error) {
          console.warn(`Failed to list tools from server ${serverId}:`, error);
        }
      }
    }

    return allTools;
  }

  async executeTool(serverId: string, toolName: string, arguments_: Record<string, any>): Promise<any> {
    const client = this.clients.get(serverId);
    if (!client) {
      throw new Error(`Server ${serverId} not found`);
    }

    const status = this.serverStatus.get(serverId);
    if (!status?.connected) {
      throw new Error(`Server ${serverId} is not connected`);
    }

    const startTime = Date.now();
    const execution: MCPToolExecution = {
      serverId,
      toolName,
      arguments: arguments_,
      timestamp: new Date()
    };

    try {
      const result = await client.callTool(toolName, arguments_);
      execution.result = result;
      execution.duration = Date.now() - startTime;
      
      this.addToHistory(execution);
      this.emit('tool:executed', execution);
      
      return result;
    } catch (error) {
      execution.error = error instanceof Error ? error.message : String(error);
      execution.duration = Date.now() - startTime;
      
      this.addToHistory(execution);
      this.emit('tool:error', execution);
      
      throw error;
    }
  }

  async listAvailableResources(): Promise<Array<MCPResource & { serverId: string }>> {
    const allResources: Array<MCPResource & { serverId: string }> = [];

    for (const [serverId, client] of this.clients) {
      const status = this.serverStatus.get(serverId);
      if (status?.connected) {
        try {
          const resources = await client.listResources();
          for (const resource of resources) {
            allResources.push({ ...resource, serverId });
          }
        } catch (error) {
          console.warn(`Failed to list resources from server ${serverId}:`, error);
        }
      }
    }

    return allResources;
  }

  async readResource(serverId: string, uri: string): Promise<any> {
    const client = this.clients.get(serverId);
    if (!client) {
      throw new Error(`Server ${serverId} not found`);
    }

    const status = this.serverStatus.get(serverId);
    if (!status?.connected) {
      throw new Error(`Server ${serverId} is not connected`);
    }

    return await client.readResource(uri);
  }

  async listAvailablePrompts(): Promise<Array<MCPPrompt & { serverId: string }>> {
    const allPrompts: Array<MCPPrompt & { serverId: string }> = [];

    for (const [serverId, client] of this.clients) {
      const status = this.serverStatus.get(serverId);
      if (status?.connected) {
        try {
          const prompts = await client.listPrompts();
          for (const prompt of prompts) {
            allPrompts.push({ ...prompt, serverId });
          }
        } catch (error) {
          console.warn(`Failed to list prompts from server ${serverId}:`, error);
        }
      }
    }

    return allPrompts;
  }

  async getPrompt(serverId: string, name: string, arguments_?: Record<string, any>): Promise<any> {
    const client = this.clients.get(serverId);
    if (!client) {
      throw new Error(`Server ${serverId} not found`);
    }

    const status = this.serverStatus.get(serverId);
    if (!status?.connected) {
      throw new Error(`Server ${serverId} is not connected`);
    }

    return await client.getPrompt(name, arguments_);
  }

  getServerStatus(serverId: string): MCPServerStatus | undefined {
    return this.serverStatus.get(serverId);
  }

  getAllServerStatus(): Map<string, MCPServerStatus> {
    return new Map(this.serverStatus);
  }

  getServerConfig(serverId: string): MCPServerConfig | undefined {
    return this.serverConfigs.get(serverId);
  }

  getAllServerConfigs(): Map<string, MCPServerConfig> {
    return new Map(this.serverConfigs);
  }

  getToolExecutionHistory(limit?: number): MCPToolExecution[] {
    const history = [...this.toolExecutionHistory].reverse(); // Most recent first
    return limit ? history.slice(0, limit) : history;
  }

  clearToolExecutionHistory(): void {
    this.toolExecutionHistory = [];
    this.emit('history:cleared');
  }

  async reconnectAllServers(): Promise<void> {
    const reconnectPromises: Promise<void>[] = [];

    for (const [serverId, config] of this.serverConfigs) {
      if (config.enabled) {
        reconnectPromises.push(
          this.connectServer(serverId).catch(error => {
            console.warn(`Failed to reconnect server ${serverId}:`, error);
          })
        );
      }
    }

    await Promise.all(reconnectPromises);
  }

  async disconnectAllServers(): Promise<void> {
    const disconnectPromises: Promise<void>[] = [];

    for (const serverId of this.clients.keys()) {
      disconnectPromises.push(
        this.disconnectServer(serverId).catch(error => {
          console.warn(`Failed to disconnect server ${serverId}:`, error);
        })
      );
    }

    await Promise.all(disconnectPromises);
  }

  private updateServerStatus(serverId: string, updates: Partial<MCPServerStatus>): void {
    const currentStatus = this.serverStatus.get(serverId);
    if (currentStatus) {
      const newStatus = { ...currentStatus, ...updates };
      this.serverStatus.set(serverId, newStatus);
      this.emit('server:status:updated', serverId, newStatus);
    }
  }

  private addToHistory(execution: MCPToolExecution): void {
    this.toolExecutionHistory.push(execution);
    
    // Trim history if it exceeds max size
    if (this.toolExecutionHistory.length > this.maxHistorySize) {
      this.toolExecutionHistory = this.toolExecutionHistory.slice(-this.maxHistorySize);
    }
  }
}