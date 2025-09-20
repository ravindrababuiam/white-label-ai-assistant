# Agency MCP Integration

A specialized integration module for connecting to the agency's existing MCP (Model Context Protocol) server. This module provides authentication, authorization, monitoring, and comprehensive testing for agency-specific MCP server interactions.

## Features

- **Secure Authentication**: Support for Bearer tokens and OAuth2 flows
- **Rate Limiting**: Configurable rate limiting per user/session
- **Capability Validation**: Automatic validation of expected tools, resources, and prompts
- **Comprehensive Monitoring**: Detailed logging, metrics collection, and health monitoring
- **Error Handling**: Robust error handling with retry policies and graceful degradation
- **Configuration Management**: Environment-based configuration with validation
- **Testing Suite**: Comprehensive unit and integration tests

## Installation

```bash
npm install
npm run build
```

## Configuration

### Environment Variables

Set the following environment variables:

```bash
# Agency MCP Server Configuration
AGENCY_MCP_ENDPOINT=https://agency-mcp.example.com/mcp
AGENCY_MCP_TOKEN=your-bearer-token-here

# Optional: OAuth2 Configuration
AGENCY_MCP_TOKEN_ENDPOINT=https://auth.agency.com/oauth/token
AGENCY_MCP_CLIENT_ID=your-client-id
AGENCY_MCP_CLIENT_SECRET=your-client-secret

# Optional: Monitoring Endpoints
AGENCY_MCP_METRICS_ENDPOINT=https://metrics.agency.com/api/metrics
AGENCY_MCP_LOGS_ENDPOINT=https://logs.agency.com/api/logs
AGENCY_MCP_ALERTS_ENDPOINT=https://alerts.agency.com/api/alerts
```

### Configuration File

The main configuration is in `config/agency-server-config.json`. This file supports environment variable substitution using `${VARIABLE_NAME}` syntax.

Example configuration:

```json
{
  "server": {
    "id": "agency-mcp-server",
    "name": "Agency MCP Server",
    "endpoint": "${AGENCY_MCP_ENDPOINT}",
    "protocol": "sse",
    "enabled": true,
    "timeout": 30000
  },
  "authentication": {
    "type": "bearer",
    "token": "${AGENCY_MCP_TOKEN}"
  },
  "capabilities": {
    "expectedTools": [
      "file_operations",
      "web_search",
      "code_execution",
      "database_query"
    ],
    "expectedResources": [
      "project_files",
      "documentation"
    ],
    "expectedPrompts": [
      "code_review",
      "documentation_generation"
    ]
  },
  "security": {
    "rateLimiting": {
      "enabled": true,
      "requestsPerMinute": 100,
      "burstLimit": 20
    }
  }
}
```

## Usage

### Basic Usage

```typescript
import { AgencyIntegrationManager } from './src/agency-integration-manager.js';

const manager = new AgencyIntegrationManager();

// Initialize with default configuration
await manager.initialize();

// Execute a tool
const response = await manager.executeTool({
  toolName: 'file_operations',
  arguments: {
    action: 'read',
    path: '/workspace/README.md'
  },
  context: {
    userId: 'user123',
    sessionId: 'session456'
  }
});

console.log('Tool result:', response.result);
```

### Advanced Usage

```typescript
import { AgencyMCPClient } from './src/agency-mcp-client.js';

// Load custom configuration
const config = await loadCustomConfig();
const client = new AgencyMCPClient(config);

// Set up event listeners
client.on('tool-executed', (execution) => {
  console.log(`Tool ${execution.toolName} executed in ${execution.duration}ms`);
});

client.on('capability-warning', (warning) => {
  console.warn(`Missing ${warning.type}:`, warning.missing);
});

// Initialize and use
await client.initialize();

const tools = await client.listAgencyTools();
const result = await client.executeAgencyTool('web_search', {
  query: 'TypeScript best practices',
  limit: 10
});
```

## API Reference

### AgencyIntegrationManager

Main manager class for agency MCP integration.

#### Methods

- `initialize(configPath?: string): Promise<void>` - Initialize the integration
- `connect(): Promise<void>` - Connect to the agency MCP server
- `disconnect(): Promise<void>` - Disconnect from the server
- `executeTool(request: AgencyToolRequest): Promise<AgencyToolResponse>` - Execute a tool
- `listAvailableTools(): Promise<any[]>` - List available tools
- `listAvailableResources(): Promise<any[]>` - List available resources
- `listAvailablePrompts(): Promise<any[]>` - List available prompts
- `healthCheck(): Promise<boolean>` - Perform health check
- `validateConfiguration(configPath?: string): Promise<ValidationResult>` - Validate configuration

#### Events

- `initialized` - Emitted when initialization completes
- `connected` - Emitted when connection is established
- `disconnected` - Emitted when connection is lost
- `tool-executed` - Emitted when a tool is successfully executed
- `tool-error` - Emitted when tool execution fails
- `status-updated` - Emitted when connection status changes

### AgencyMCPClient

Low-level client for direct agency MCP server communication.

#### Methods

- `initialize(): Promise<void>` - Initialize the client
- `executeAgencyTool(toolName, arguments, context?): Promise<any>` - Execute a tool
- `listAgencyTools(): Promise<any[]>` - List available tools
- `listAgencyResources(): Promise<any[]>` - List available resources
- `readAgencyResource(uri): Promise<any>` - Read resource content
- `listAgencyPrompts(): Promise<any[]>` - List available prompts
- `getAgencyPrompt(name, arguments?): Promise<any>` - Get prompt content
- `getMetrics(): AgencyMetrics` - Get performance metrics

## Authentication

### Bearer Token Authentication

```json
{
  "authentication": {
    "type": "bearer",
    "token": "${AGENCY_MCP_TOKEN}"
  }
}
```

### OAuth2 Client Credentials Flow

```json
{
  "authentication": {
    "type": "oauth2",
    "tokenEndpoint": "${AGENCY_MCP_TOKEN_ENDPOINT}",
    "clientId": "${AGENCY_MCP_CLIENT_ID}",
    "clientSecret": "${AGENCY_MCP_CLIENT_SECRET}"
  }
}
```

The OAuth2 flow automatically handles token refresh when tokens expire.

## Rate Limiting

Rate limiting is enforced per user/session:

```json
{
  "security": {
    "rateLimiting": {
      "enabled": true,
      "requestsPerMinute": 100,
      "burstLimit": 20
    }
  }
}
```

- `requestsPerMinute`: Maximum requests per user per minute
- `burstLimit`: Maximum burst requests allowed

## Monitoring and Logging

### Metrics Collection

The integration automatically collects metrics:

- Total requests
- Successful/failed requests
- Average response time
- Uptime percentage
- Rate limit hits
- Authentication failures

### Detailed Logging

When enabled, all tool executions are logged:

```json
{
  "monitoring": {
    "enableDetailedLogging": true,
    "logsEndpoint": "${AGENCY_MCP_LOGS_ENDPOINT}",
    "logLevel": "INFO"
  }
}
```

Log entries include:
- Timestamp
- Tool name
- User/session context
- Execution duration
- Success/failure status
- Error details (if any)

## Testing

### Unit Tests

```bash
npm test
```

### Integration Tests

```bash
npm run test:integration
```

### Coverage Report

```bash
npm run test:coverage
```

### Test Configuration

Create a test configuration file for integration tests:

```json
{
  "server": {
    "id": "test-agency-server",
    "endpoint": "https://test-agency-mcp.example.com/mcp",
    "protocol": "sse"
  },
  "authentication": {
    "type": "bearer",
    "token": "test-token"
  }
}
```

## Configuration Validation

Validate your configuration before deployment:

```bash
npm run validate-config
```

Or programmatically:

```typescript
const manager = new AgencyIntegrationManager();
const result = await manager.validateConfiguration('./config/agency-server-config.json');

if (!result.valid) {
  console.error('Configuration errors:', result.errors);
}
```

## Error Handling

The integration provides comprehensive error handling:

### Connection Errors
- Automatic retry with exponential backoff
- Configurable retry policies
- Graceful degradation when server is unavailable

### Authentication Errors
- Automatic token refresh for OAuth2
- Clear error messages for invalid credentials
- Metrics tracking for authentication failures

### Tool Execution Errors
- Detailed error reporting
- Execution history tracking
- Timeout handling

### Rate Limiting
- Per-user rate limiting
- Clear error messages when limits are exceeded
- Metrics tracking for rate limit hits

## Security Considerations

- Store authentication tokens securely using environment variables
- Use HTTPS endpoints for all communications
- Implement proper access controls for MCP server access
- Regularly rotate authentication credentials
- Monitor execution logs for suspicious activity
- Validate all tool inputs to prevent injection attacks

## Troubleshooting

### Common Issues

#### Connection Failed
```
Error: Connection failed
```
- Check server endpoint URL
- Verify network connectivity
- Ensure server is running and accessible

#### Authentication Failed
```
Error: OAuth2 authentication failed
```
- Verify client credentials
- Check token endpoint URL
- Ensure required scopes are configured

#### Rate Limit Exceeded
```
Error: Rate limit exceeded
```
- Check rate limiting configuration
- Monitor user request patterns
- Consider increasing limits if appropriate

#### Tool Not Found
```
Error: Tool 'tool_name' not found
```
- Verify tool is available on server
- Check capability validation warnings
- Ensure server is properly configured

### Debug Mode

Enable debug logging:

```bash
export NODE_ENV=development
export DEBUG=agency-mcp:*
```

### Health Monitoring

Monitor server health:

```typescript
const isHealthy = await manager.healthCheck();
if (!isHealthy) {
  console.error('Agency MCP server is not healthy');
}
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

MIT License - see LICENSE file for details.