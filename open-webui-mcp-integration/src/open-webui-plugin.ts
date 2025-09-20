import { MCPManager } from './mcp-manager.js';
import type { MCPServerConfig } from './mcp-manager.js';

// Open WebUI Plugin Interface
export interface OpenWebUIPlugin {
  id: string;
  name: string;
  version: string;
  description: string;
  author: string;
  initialize: (context: OpenWebUIContext) => Promise<void>;
  destroy: () => Promise<void>;
}

export interface OpenWebUIContext {
  // Open WebUI API methods
  addSidebarItem: (item: SidebarItem) => void;
  removeSidebarItem: (id: string) => void;
  addChatAction: (action: ChatAction) => void;
  removeChatAction: (id: string) => void;
  addSettingsTab: (tab: SettingsTab) => void;
  removeSettingsTab: (id: string) => void;
  
  // Event system
  on: (event: string, handler: Function) => void;
  off: (event: string, handler: Function) => void;
  emit: (event: string, ...args: any[]) => void;
  
  // Storage
  storage: {
    get: (key: string) => Promise<any>;
    set: (key: string, value: any) => Promise<void>;
    remove: (key: string) => Promise<void>;
  };
  
  // UI utilities
  showNotification: (message: string, type?: 'info' | 'success' | 'warning' | 'error') => void;
  showModal: (component: any, props?: any) => Promise<any>;
  
  // Chat integration
  addMessageProcessor: (processor: MessageProcessor) => void;
  removeMessageProcessor: (id: string) => void;
}

export interface SidebarItem {
  id: string;
  label: string;
  icon: string;
  component: any;
  order?: number;
}

export interface ChatAction {
  id: string;
  label: string;
  icon: string;
  handler: (message: string, context: any) => Promise<string | void>;
  condition?: (message: string, context: any) => boolean;
}

export interface SettingsTab {
  id: string;
  label: string;
  icon: string;
  component: any;
  order?: number;
}

export interface MessageProcessor {
  id: string;
  priority: number;
  process: (message: string, context: any) => Promise<string>;
}

// MCP Plugin Implementation
export class MCPOpenWebUIPlugin implements OpenWebUIPlugin {
  id = 'mcp-integration';
  name = 'MCP Integration';
  version = '1.0.0';
  description = 'Model Context Protocol integration for Open WebUI';
  author = 'White-label AI Assistant Team';

  private mcpManager: MCPManager;
  private context: OpenWebUIContext | null = null;
  private initialized = false;

  constructor() {
    this.mcpManager = new MCPManager();
  }

  async initialize(context: OpenWebUIContext): Promise<void> {
    if (this.initialized) {
      return;
    }

    this.context = context;

    // Load saved server configurations
    await this.loadServerConfigurations();

    // Add MCP sidebar item
    context.addSidebarItem({
      id: 'mcp-servers',
      label: 'MCP Servers',
      icon: 'server',
      component: 'MCPServerList',
      order: 100
    });

    // Add MCP tools sidebar item
    context.addSidebarItem({
      id: 'mcp-tools',
      label: 'MCP Tools',
      icon: 'tool',
      component: 'MCPToolPanel',
      order: 101
    });

    // Add MCP settings tab
    context.addSettingsTab({
      id: 'mcp-settings',
      label: 'MCP Integration',
      icon: 'settings',
      component: 'MCPSettings',
      order: 200
    });

    // Add chat actions for MCP tools
    context.addChatAction({
      id: 'mcp-tool-suggest',
      label: 'Suggest MCP Tools',
      icon: 'lightbulb',
      handler: this.suggestMCPTools.bind(this),
      condition: (message) => message.includes('tool') || message.includes('function')
    });

    // Add message processor for MCP tool execution
    context.addMessageProcessor({
      id: 'mcp-tool-processor',
      priority: 10,
      process: this.processMCPToolRequests.bind(this)
    });

    // Set up event listeners
    this.setupEventListeners();

    this.initialized = true;

    context.showNotification('MCP Integration plugin initialized', 'success');
  }

  async destroy(): Promise<void> {
    if (!this.initialized || !this.context) {
      return;
    }

    // Disconnect all servers
    await this.mcpManager.disconnectAllServers();

    // Remove UI components
    this.context.removeSidebarItem('mcp-servers');
    this.context.removeSidebarItem('mcp-tools');
    this.context.removeSettingsTab('mcp-settings');
    this.context.removeChatAction('mcp-tool-suggest');
    this.context.removeMessageProcessor('mcp-tool-processor');

    this.initialized = false;
    this.context = null;
  }

  private async loadServerConfigurations(): Promise<void> {
    if (!this.context) return;

    try {
      const savedConfigs = await this.context.storage.get('mcp-server-configs');
      if (savedConfigs && Array.isArray(savedConfigs)) {
        for (const config of savedConfigs) {
          await this.mcpManager.addServer(config);
        }
      }
    } catch (error) {
      console.warn('Failed to load MCP server configurations:', error);
    }
  }

  private async saveServerConfigurations(): Promise<void> {
    if (!this.context) return;

    try {
      const configs = Array.from(this.mcpManager.getAllServerConfigs().values());
      await this.context.storage.set('mcp-server-configs', configs);
    } catch (error) {
      console.warn('Failed to save MCP server configurations:', error);
    }
  }

  private setupEventListeners(): void {
    if (!this.context) return;

    // Listen for MCP manager events
    this.mcpManager.on('server:added', () => {
      this.saveServerConfigurations();
    });

    this.mcpManager.on('server:removed', () => {
      this.saveServerConfigurations();
    });

    this.mcpManager.on('server:connected', (serverId: string) => {
      this.context?.showNotification(`MCP server ${serverId} connected`, 'success');
    });

    this.mcpManager.on('server:disconnected', (serverId: string) => {
      this.context?.showNotification(`MCP server ${serverId} disconnected`, 'warning');
    });

    this.mcpManager.on('server:error', (serverId: string, error: Error) => {
      this.context?.showNotification(`MCP server ${serverId} error: ${error.message}`, 'error');
    });

    this.mcpManager.on('tool:executed', (execution: any) => {
      this.context?.emit('mcp:tool:executed', execution);
    });

    this.mcpManager.on('tool:error', (execution: any) => {
      this.context?.emit('mcp:tool:error', execution);
    });
  }

  private async suggestMCPTools(message: string, context: any): Promise<string> {
    try {
      const tools = await this.mcpManager.listAvailableTools();
      
      if (tools.length === 0) {
        return 'No MCP tools are currently available. Make sure MCP servers are connected.';
      }

      const suggestions = tools.map(tool => 
        `- **${tool.name}** (${tool.serverId}): ${tool.description}`
      ).join('\n');

      return `Available MCP tools:\n\n${suggestions}\n\nYou can execute these tools using the MCP Tools panel or by asking me to use a specific tool.`;
    } catch (error) {
      return `Failed to load MCP tools: ${error instanceof Error ? error.message : 'Unknown error'}`;
    }
  }

  private async processMCPToolRequests(message: string, context: any): Promise<string> {
    // Look for tool execution patterns in the message
    const toolExecutionPattern = /execute\s+(?:mcp\s+)?tool\s+([a-zA-Z0-9_-]+)(?:\s+with\s+(.+))?/i;
    const match = message.match(toolExecutionPattern);

    if (!match) {
      return message; // No tool execution request found
    }

    const toolName = match[1];
    const argumentsStr = match[2];

    try {
      // Find the tool
      const tools = await this.mcpManager.listAvailableTools();
      const tool = tools.find(t => t.name.toLowerCase() === toolName.toLowerCase());

      if (!tool) {
        return `Tool "${toolName}" not found. Available tools: ${tools.map(t => t.name).join(', ')}`;
      }

      // Parse arguments if provided
      let toolArguments: Record<string, any> = {};
      if (argumentsStr) {
        try {
          // Try to parse as JSON first
          toolArguments = JSON.parse(argumentsStr);
        } catch {
          // If not JSON, try to parse as key=value pairs
          const pairs = argumentsStr.split(',').map(pair => pair.trim());
          for (const pair of pairs) {
            const [key, value] = pair.split('=').map(s => s.trim());
            if (key && value) {
              toolArguments[key] = value;
            }
          }
        }
      }

      // Execute the tool
      const result = await this.mcpManager.executeTool(tool.serverId, tool.name, toolArguments);

      // Format the result
      const resultStr = typeof result === 'string' ? result : JSON.stringify(result, null, 2);
      return `Executed MCP tool "${tool.name}" from server "${tool.serverId}":\n\n\`\`\`\n${resultStr}\n\`\`\``;

    } catch (error) {
      return `Failed to execute MCP tool "${toolName}": ${error instanceof Error ? error.message : 'Unknown error'}`;
    }
  }

  // Public API for other plugins or components
  getMCPManager(): MCPManager {
    return this.mcpManager;
  }

  async addServer(config: MCPServerConfig): Promise<void> {
    await this.mcpManager.addServer(config);
  }

  async removeServer(serverId: string): Promise<void> {
    await this.mcpManager.removeServer(serverId);
  }

  async executeToolFromChat(serverId: string, toolName: string, arguments_: Record<string, any>): Promise<any> {
    return await this.mcpManager.executeTool(serverId, toolName, arguments_);
  }
}

// Plugin factory function for Open WebUI
export function createMCPPlugin(): OpenWebUIPlugin {
  return new MCPOpenWebUIPlugin();
}

// Default export for Open WebUI plugin system
export default createMCPPlugin;