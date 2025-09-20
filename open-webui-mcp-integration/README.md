# Open WebUI MCP Integration

A comprehensive plugin for integrating Model Context Protocol (MCP) servers with Open WebUI, enabling seamless tool execution, resource access, and prompt management within the chat interface.

## Features

- **MCP Server Management**: Add, configure, and manage multiple MCP servers
- **Protocol Support**: Full support for stdio, SSE, and WebSocket MCP transports
- **Authentication**: Support for Bearer tokens, API keys, and basic authentication
- **Tool Execution**: Execute MCP tools directly from the chat interface or dedicated panel
- **Resource Access**: Browse and access MCP server resources
- **Prompt Management**: Use MCP server prompts in conversations
- **Real-time Monitoring**: Health monitoring and status tracking for all servers
- **Execution History**: Track and review tool execution history
- **Chat Integration**: Natural language tool execution through chat commands

## Installation

### As an Open WebUI Plugin

1. Copy the plugin files to your Open WebUI plugins directory:
```bash
cp -r open-webui-mcp-integration /path/to/open-webui/plugins/
```

2. Install dependencies:
```bash
cd /path/to/open-webui/plugins/open-webui-mcp-integration
npm install
```

3. Build the plugin:
```bash
npm run build
```

4. Restart Open WebUI to load the plugin.

### Development Setup

1. Clone the repository:
```bash
git clone <repository-url>
cd open-webui-mcp-integration
```

2. Install dependencies:
```bash
npm install
```

3. Start development server:
```bash
npm run dev
```

## Usage

### Adding MCP Servers

1. Navigate to the MCP Servers panel in the Open WebUI sidebar
2. Click "Add Server" to open the configuration form
3. Fill in the server details:
   - **Server ID**: Unique identifier for the server
   - **Name**: Human-readable name
   - **Protocol**: Choose between stdio, SSE, or WebSocket
   - **Endpoint**: Server endpoint URL or command
   - **Authentication**: Configure authentication if required

### Server Configuration Examples

#### SSE Server
```json
{
  "id": "agency-server",
  "name": "Agency MCP Server",
  "protocol": "sse",
  "endpoint": "https://agency-mcp.example.com/events",
  "authentication": {
    "type": "bearer",
    "token": "your-bearer-token"
  }
}
```

#### WebSocket Server
```json
{
  "id": "database-server",
  "name": "Database MCP Server",
  "protocol": "websocket",
  "endpoint": "wss://db-mcp.example.com/ws",
  "authentication": {
    "type": "api-key",
    "token": "your-api-key",
    "header": "X-API-Key"
  }
}
```

#### Stdio Server
```json
{
  "id": "local-filesystem",
  "name": "Local Filesystem Server",
  "protocol": "stdio",
  "endpoint": "stdio://local",
  "command": "uvx",
  "args": ["mcp-server-filesystem", "/workspace"],
  "env": {
    "PYTHONPATH": "/usr/local/lib/python3.11/site-packages"
  }
}
```

### Using MCP Tools

#### Through the Tools Panel
1. Navigate to the MCP Tools panel
2. Browse available tools from connected servers
3. Select a tool to see its parameters
4. Fill in the required arguments
5. Click "Execute Tool" to run it

#### Through Chat Commands
You can execute MCP tools directly from the chat using natural language:

```
Execute MCP tool file_read with {"path": "/workspace/README.md"}
```

```
Execute tool database_query with query="SELECT * FROM users LIMIT 10"
```

### Tool Execution Examples

#### File Operations
```
Execute tool file_list with {"directory": "/workspace"}
Execute tool file_read with {"path": "/workspace/config.json"}
Execute tool file_write with {"path": "/tmp/output.txt", "content": "Hello World"}
```

#### Database Operations
```
Execute tool db_query with {"sql": "SELECT COUNT(*) FROM users"}
Execute tool db_insert with {"table": "logs", "data": {"message": "Test log", "level": "info"}}
```

#### Web Scraping
```
Execute tool web_scrape with {"url": "https://example.com", "selector": ".content"}
Execute tool web_screenshot with {"url": "https://example.com", "width": 1200}
```

### Managing Server Connections

- **Enable/Disable**: Toggle servers on/off without removing configuration
- **Connect/Disconnect**: Manually control server connections
- **Health Monitoring**: View real-time connection status and error messages
- **Auto-Connect**: Automatically connect enabled servers on startup

### Execution History

The plugin maintains a history of all tool executions, including:
- Tool name and server
- Execution timestamp
- Duration
- Success/failure status
- Error messages (if any)
- Results (for successful executions)

## API Reference

### MCPManager

The core manager class for handling MCP server operations:

```typescript
import { MCPManager } from './mcp-manager.js';

const manager = new MCPManager();

// Add a server
await manager.addServer({
  id: 'my-server',
  name: 'My MCP Server',
  endpoint: 'https://api.example.com/mcp',
  protocol: 'sse',
  enabled: true
});

// Execute a tool
const result = await manager.executeTool('my-server', 'my-tool', {
  param1: 'value1',
  param2: 'value2'
});

// List available tools
const tools = await manager.listAvailableTools();
```

### MCPClient

Low-level client for direct MCP protocol communication:

```typescript
import { MCPClient } from './mcp-client.js';

const client = new MCPClient('server-id', 'https://api.example.com/mcp', 'sse');

await client.connect();
await client.initialize({ roots: { listChanged: true } });

const tools = await client.listTools();
const result = await client.callTool('tool-name', { arg: 'value' });
```

## Events

The plugin emits various events that you can listen to:

```typescript
// Server events
mcpManager.on('server:connected', (serverId) => {
  console.log(`Server ${serverId} connected`);
});

mcpManager.on('server:disconnected', (serverId) => {
  console.log(`Server ${serverId} disconnected`);
});

mcpManager.on('server:error', (serverId, error) => {
  console.error(`Server ${serverId} error:`, error);
});

// Tool execution events
mcpManager.on('tool:executed', (execution) => {
  console.log('Tool executed:', execution);
});

mcpManager.on('tool:error', (execution) => {
  console.error('Tool execution failed:', execution);
});
```

## Configuration

### Plugin Configuration

The plugin stores its configuration in Open WebUI's storage system:

- **mcp-server-configs**: Array of server configurations
- **mcp-settings**: Plugin settings and preferences

### Environment Variables

For stdio servers, you can use environment variables:

```json
{
  "env": {
    "PYTHONPATH": "/usr/local/lib/python3.11/site-packages",
    "LOG_LEVEL": "INFO",
    "API_KEY": "${MCP_API_KEY}"
  }
}
```

## Security Considerations

- Store sensitive authentication tokens securely
- Use HTTPS/WSS endpoints for production deployments
- Validate tool inputs to prevent injection attacks
- Implement proper access controls for MCP servers
- Regularly rotate authentication credentials
- Monitor tool execution logs for suspicious activity

## Troubleshooting

### Common Issues

#### Server Connection Failed
- Check server endpoint URL and protocol
- Verify authentication credentials
- Ensure server is running and accessible
- Check network connectivity and firewall settings

#### Tool Execution Timeout
- Increase timeout settings in server configuration
- Check server performance and load
- Verify tool parameters are correct
- Monitor server logs for errors

#### Authentication Errors
- Verify token/credentials are correct and not expired
- Check authentication type matches server requirements
- Ensure proper header names for API key authentication

### Debug Mode

Enable debug logging by setting the log level:

```typescript
// In browser console
localStorage.setItem('mcp-debug', 'true');
```

### Health Checks

Monitor server health through the status indicators:
- 🟢 Green: Connected and healthy
- 🟡 Yellow: Connected but with warnings
- 🔴 Red: Disconnected or error state
- ⚪ Gray: Disabled

## Development

### Building

```bash
npm run build
```

### Testing

```bash
npm test
npm run test:coverage
```

### Linting

```bash
npm run lint
npm run lint:fix
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## License

MIT License - see LICENSE file for details.

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review server logs and browser console
3. Create an issue with detailed error information
4. Include server configuration (without sensitive data)