import { EventEmitter } from 'events';

export interface MCPMessage {
  jsonrpc: '2.0';
  id?: string | number;
  method?: string;
  params?: any;
  result?: any;
  error?: {
    code: number;
    message: string;
    data?: any;
  };
}

export interface MCPTool {
  name: string;
  description: string;
  inputSchema: {
    type: 'object';
    properties: Record<string, any>;
    required?: string[];
  };
}

export interface MCPResource {
  uri: string;
  name: string;
  description?: string;
  mimeType?: string;
}

export interface MCPPrompt {
  name: string;
  description: string;
  arguments?: Array<{
    name: string;
    description: string;
    required?: boolean;
  }>;
}

export interface MCPServerCapabilities {
  tools?: {
    listChanged?: boolean;
  };
  resources?: {
    subscribe?: boolean;
    listChanged?: boolean;
  };
  prompts?: {
    listChanged?: boolean;
  };
  logging?: {};
}

export interface MCPClientCapabilities {
  roots?: {
    listChanged?: boolean;
  };
  sampling?: {};
}

export interface MCPServerInfo {
  name: string;
  version: string;
  capabilities: MCPServerCapabilities;
}

export class MCPClient extends EventEmitter {
  private serverId: string;
  private serverEndpoint: string;
  private protocol: 'stdio' | 'sse' | 'websocket';
  private connection: any = null;
  private isConnected = false;
  private messageId = 0;
  private pendingRequests = new Map<string | number, {
    resolve: (value: any) => void;
    reject: (error: any) => void;
    timeout: NodeJS.Timeout;
  }>();

  constructor(serverId: string, serverEndpoint: string, protocol: 'stdio' | 'sse' | 'websocket' = 'sse') {
    super();
    this.serverId = serverId;
    this.serverEndpoint = serverEndpoint;
    this.protocol = protocol;
  }

  async connect(authentication?: any): Promise<void> {
    if (this.isConnected) {
      return;
    }

    try {
      switch (this.protocol) {
        case 'sse':
          await this.connectSSE(authentication);
          break;
        case 'websocket':
          await this.connectWebSocket(authentication);
          break;
        case 'stdio':
          await this.connectStdio(authentication);
          break;
        default:
          throw new Error(`Unsupported protocol: ${this.protocol}`);
      }

      this.isConnected = true;
      this.emit('connected');
    } catch (error) {
      this.emit('error', error);
      throw error;
    }
  }

  async disconnect(): Promise<void> {
    if (!this.isConnected) {
      return;
    }

    // Clear pending requests
    for (const [id, request] of this.pendingRequests) {
      clearTimeout(request.timeout);
      request.reject(new Error('Connection closed'));
    }
    this.pendingRequests.clear();

    // Close connection based on protocol
    if (this.connection) {
      switch (this.protocol) {
        case 'sse':
          this.connection.close();
          break;
        case 'websocket':
          this.connection.close();
          break;
        case 'stdio':
          if (this.connection.kill) {
            this.connection.kill();
          }
          break;
      }
      this.connection = null;
    }

    this.isConnected = false;
    this.emit('disconnected');
  }

  async initialize(clientCapabilities: MCPClientCapabilities): Promise<MCPServerInfo> {
    const response = await this.sendRequest('initialize', {
      protocolVersion: '2024-11-05',
      capabilities: clientCapabilities,
      clientInfo: {
        name: 'Open WebUI MCP Client',
        version: '1.0.0'
      }
    });

    return response;
  }

  async listTools(): Promise<MCPTool[]> {
    const response = await this.sendRequest('tools/list');
    return response.tools || [];
  }

  async callTool(name: string, arguments_: Record<string, any>): Promise<any> {
    const response = await this.sendRequest('tools/call', {
      name,
      arguments: arguments_
    });
    return response;
  }

  async listResources(): Promise<MCPResource[]> {
    const response = await this.sendRequest('resources/list');
    return response.resources || [];
  }

  async readResource(uri: string): Promise<any> {
    const response = await this.sendRequest('resources/read', { uri });
    return response;
  }

  async listPrompts(): Promise<MCPPrompt[]> {
    const response = await this.sendRequest('prompts/list');
    return response.prompts || [];
  }

  async getPrompt(name: string, arguments_?: Record<string, any>): Promise<any> {
    const response = await this.sendRequest('prompts/get', {
      name,
      arguments: arguments_
    });
    return response;
  }

  private async sendRequest(method: string, params?: any, timeout: number = 30000): Promise<any> {
    if (!this.isConnected) {
      throw new Error('Not connected to MCP server');
    }

    const id = ++this.messageId;
    const message: MCPMessage = {
      jsonrpc: '2.0',
      id,
      method,
      params
    };

    return new Promise((resolve, reject) => {
      const timeoutHandle = setTimeout(() => {
        this.pendingRequests.delete(id);
        reject(new Error(`Request timeout: ${method}`));
      }, timeout);

      this.pendingRequests.set(id, {
        resolve: (result) => {
          clearTimeout(timeoutHandle);
          resolve(result);
        },
        reject: (error) => {
          clearTimeout(timeoutHandle);
          reject(error);
        },
        timeout: timeoutHandle
      });

      this.sendMessage(message);
    });
  }

  private sendMessage(message: MCPMessage): void {
    const messageStr = JSON.stringify(message);

    switch (this.protocol) {
      case 'sse':
        // For SSE, we would typically send via a separate HTTP endpoint
        this.sendSSEMessage(messageStr);
        break;
      case 'websocket':
        if (this.connection && this.connection.readyState === WebSocket.OPEN) {
          this.connection.send(messageStr);
        }
        break;
      case 'stdio':
        if (this.connection && this.connection.stdin) {
          this.connection.stdin.write(messageStr + '\n');
        }
        break;
    }
  }

  private handleMessage(message: MCPMessage): void {
    if (message.id && this.pendingRequests.has(message.id)) {
      const request = this.pendingRequests.get(message.id)!;
      this.pendingRequests.delete(message.id);

      if (message.error) {
        request.reject(new Error(`MCP Error: ${message.error.message}`));
      } else {
        request.resolve(message.result);
      }
    } else if (message.method) {
      // Handle notifications and requests from server
      this.emit('notification', message.method, message.params);
    }
  }

  private async connectSSE(authentication?: any): Promise<void> {
    const headers: Record<string, string> = {
      'Accept': 'text/event-stream',
      'Cache-Control': 'no-cache'
    };

    if (authentication) {
      this.addAuthHeaders(headers, authentication);
    }

    const eventSource = new EventSource(this.serverEndpoint, {
      // Note: EventSource doesn't support custom headers in browser
      // This would need to be implemented differently in a real browser environment
    });

    eventSource.onopen = () => {
      this.connection = eventSource;
    };

    eventSource.onmessage = (event) => {
      try {
        const message = JSON.parse(event.data);
        this.handleMessage(message);
      } catch (error) {
        this.emit('error', new Error(`Failed to parse SSE message: ${error}`));
      }
    };

    eventSource.onerror = (error) => {
      this.emit('error', error);
    };

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('SSE connection timeout'));
      }, 10000);

      eventSource.onopen = () => {
        clearTimeout(timeout);
        this.connection = eventSource;
        resolve();
      };
    });
  }

  private async connectWebSocket(authentication?: any): Promise<void> {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(this.serverEndpoint);

      const timeout = setTimeout(() => {
        ws.close();
        reject(new Error('WebSocket connection timeout'));
      }, 10000);

      ws.onopen = () => {
        clearTimeout(timeout);
        this.connection = ws;
        resolve();
      };

      ws.onmessage = (event) => {
        try {
          const message = JSON.parse(event.data);
          this.handleMessage(message);
        } catch (error) {
          this.emit('error', new Error(`Failed to parse WebSocket message: ${error}`));
        }
      };

      ws.onerror = (error) => {
        clearTimeout(timeout);
        reject(error);
      };

      ws.onclose = () => {
        this.isConnected = false;
        this.emit('disconnected');
      };
    });
  }

  private async connectStdio(authentication?: any): Promise<void> {
    // Note: This would typically use child_process.spawn in Node.js
    // For browser environment, this would need a different implementation
    throw new Error('Stdio protocol not supported in browser environment');
  }

  private sendSSEMessage(message: string): void {
    // For SSE, we typically need a separate HTTP endpoint to send messages
    // This is a simplified implementation
    fetch(this.serverEndpoint.replace('/events', '/send'), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: message
    }).catch(error => {
      this.emit('error', error);
    });
  }

  private addAuthHeaders(headers: Record<string, string>, authentication: any): void {
    switch (authentication.type) {
      case 'bearer':
        headers['Authorization'] = `Bearer ${authentication.token}`;
        break;
      case 'api-key':
        const headerName = authentication.header || 'X-API-Key';
        headers[headerName] = authentication.token;
        break;
      case 'basic':
        const credentials = btoa(`${authentication.username}:${authentication.password}`);
        headers['Authorization'] = `Basic ${credentials}`;
        break;
    }
  }

  getServerId(): string {
    return this.serverId;
  }

  isConnectionActive(): boolean {
    return this.isConnected;
  }
}