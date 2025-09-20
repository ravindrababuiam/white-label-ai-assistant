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
export declare class MCPClient extends EventEmitter {
    private serverId;
    private serverEndpoint;
    private protocol;
    private connection;
    private isConnected;
    private messageId;
    private pendingRequests;
    constructor(serverId: string, serverEndpoint: string, protocol?: 'stdio' | 'sse' | 'websocket');
    connect(authentication?: any): Promise<void>;
    disconnect(): Promise<void>;
    initialize(clientCapabilities: MCPClientCapabilities): Promise<MCPServerInfo>;
    listTools(): Promise<MCPTool[]>;
    callTool(name: string, arguments_: Record<string, any>): Promise<any>;
    listResources(): Promise<MCPResource[]>;
    readResource(uri: string): Promise<any>;
    listPrompts(): Promise<MCPPrompt[]>;
    getPrompt(name: string, arguments_?: Record<string, any>): Promise<any>;
    private sendRequest;
    private sendMessage;
    private handleMessage;
    private connectSSE;
    private connectWebSocket;
    private connectStdio;
    private sendSSEMessage;
    private addAuthHeaders;
    getServerId(): string;
    isConnectionActive(): boolean;
}
//# sourceMappingURL=mcp-client.d.ts.map