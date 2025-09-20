# MCP Server Configuration Framework

A comprehensive framework for managing Model Context Protocol (MCP) servers in the white-label AI assistant platform. This framework provides configuration validation, server registration, health monitoring, and a REST API for managing MCP servers.

## Features

- **Configuration Schema Validation**: JSON Schema-based validation for MCP server configurations
- **Server Registry**: Centralized registration and management of MCP servers
- **Health Monitoring**: Automated health checks with configurable intervals and retry policies
- **REST API**: Complete API for server management operations
- **Multiple Protocols**: Support for stdio, SSE, and WebSocket MCP transports
- **Authentication**: Support for various authentication methods (Bearer, API Key, Basic Auth)
- **Metrics Collection**: Performance and availability metrics for each server

## Installation

```bash
npm install
npm run build
```

## Quick Start

```typescript
import { MCPServerFramework } from './src/index.js';

// Create and start the framework
const framework = new MCPServerFramework();
await framework.start(3000);

// Register a server
const registry = framework.getRegistry();
await registry.registerServer({
  id: 'example-server',
  name: 'Example MCP Server',
  endpoint: 'https://api.example.com/mcp',
  protocol: 'sse',
  authentication: {
    type: 'bearer',
    token: 'your-api-token'
  },
  enabled: true
}, 'admin-user');

console.log('MCP Server Framework is running!');
```

## Configuration Schema

### Basic Server Configuration

```json
{
  "id": "unique-server-id",
  "name": "Human Readable Name",
  "description": "Optional description",
  "endpoint": "https://api.example.com/mcp",
  "protocol": "sse",
  "enabled": true,
  "tags": ["category1", "category2"]
}
```

### Stdio Protocol Configuration

```json
{
  "id": "stdio-server",
  "name": "Local MCP Server",
  "endpoint": "stdio://local",
  "protocol": "stdio",
  "command": "python",
  "args": ["-m", "my_mcp_server"],
  "env": {
    "PYTHONPATH": "/path/to/server",
    "LOG_LEVEL": "INFO"
  }
}
```

### Authentication Configuration

```json
{
  "authentication": {
    "type": "bearer",
    "token": "your-bearer-token"
  }
}
```

```json
{
  "authentication": {
    "type": "api-key",
    "token": "your-api-key",
    "header": "X-API-Key"
  }
}
```

```json
{
  "authentication": {
    "type": "basic",
    "username": "your-username",
    "password": "your-password"
  }
}
```

### Health Check Configuration

```json
{
  "healthCheck": {
    "enabled": true,
    "interval": 30000,
    "timeout": 5000,
    "retries": 3
  }
}
```

### Retry Policy Configuration

```json
{
  "retryPolicy": {
    "enabled": true,
    "maxRetries": 3,
    "backoffMultiplier": 2,
    "initialDelay": 1000
  }
}
```

## API Endpoints

### Server Management

- `GET /servers` - List all servers with optional filtering and pagination
- `GET /servers/:id` - Get specific server details
- `POST /servers` - Register a new server
- `PUT /servers/:id` - Update existing server
- `DELETE /servers/:id` - Unregister server

### Health Monitoring

- `GET /servers/:id/health` - Get server health status and metrics
- `GET /servers/health/all` - Get health status for all servers
- `POST /servers/:id/health-check` - Perform immediate health check

### Server Control

- `POST /servers/:id/enable` - Enable server
- `POST /servers/:id/disable` - Disable server

### Configuration Validation

- `POST /validate` - Validate server configuration list

## API Examples

### Register a New Server

```bash
curl -X POST http://localhost:3000/servers \
  -H "Content-Type: application/json" \
  -d '{
    "id": "example-server",
    "name": "Example Server",
    "endpoint": "https://api.example.com",
    "protocol": "sse",
    "enabled": true,
    "registeredBy": "admin"
  }'
```

### List Servers with Filtering

```bash
# Get enabled servers only
curl "http://localhost:3000/servers?enabled=true"

# Get servers by protocol
curl "http://localhost:3000/servers?protocol=sse"

# Get servers with pagination
curl "http://localhost:3000/servers?page=1&limit=10"

# Get servers with sorting
curl "http://localhost:3000/servers?sortBy=name&sortOrder=asc"
```

### Check Server Health

```bash
curl http://localhost:3000/servers/example-server/health
```

### Perform Health Check

```bash
curl -X POST http://localhost:3000/servers/example-server/health-check
```

## Events

The framework emits various events that you can listen to:

```typescript
const registry = framework.getRegistry();

// Server lifecycle events
registry.on('server:registered', (serverId, registration) => {
  console.log(`Server ${serverId} registered`);
});

registry.on('server:updated', (serverId, registration) => {
  console.log(`Server ${serverId} updated`);
});

registry.on('server:unregistered', (serverId, registration) => {
  console.log(`Server ${serverId} unregistered`);
});

// Health monitoring events
registry.on('server:status:changed', (serverId, newStatus, oldStatus) => {
  console.log(`Server ${serverId} status changed from ${oldStatus} to ${newStatus}`);
});

registry.on('server:health:checked', (serverId, result) => {
  console.log(`Health check for ${serverId}: ${result.success ? 'OK' : 'FAILED'}`);
});
```

## Testing

```bash
# Run tests
npm test

# Run tests with coverage
npm run test:coverage

# Run tests in watch mode
npm run dev
```

## Development

```bash
# Install dependencies
npm install

# Build the project
npm run build

# Start in development mode
npm run dev

# Lint code
npm run lint
npm run lint:fix
```

## Configuration Validation

The framework includes comprehensive validation for all configuration options:

- **ID Format**: Must match `^[a-zA-Z0-9-_]+$`
- **Endpoint**: Must be a valid URL
- **Protocol**: Must be one of `stdio`, `sse`, or `websocket`
- **Authentication**: Type-specific validation for tokens, credentials
- **Health Check**: Validation of intervals, timeouts, and retry counts
- **WebSocket Endpoints**: Must start with `ws://` or `wss://`
- **Stdio Commands**: Command is required for stdio protocol

## Error Handling

The framework provides detailed error information:

```json
{
  "error": "Validation failed",
  "details": [
    {
      "field": "authentication.token",
      "message": "Token is required for bearer authentication",
      "value": null
    }
  ]
}
```

## Monitoring and Metrics

Each server tracks the following metrics:

- **Total Requests**: Number of requests processed
- **Successful Requests**: Number of successful requests
- **Failed Requests**: Number of failed requests
- **Average Response Time**: Average response time in milliseconds
- **Uptime Percentage**: Percentage of successful health checks
- **Last Request Time**: Timestamp of last request

## Security Considerations

- Store sensitive authentication tokens securely
- Use HTTPS endpoints for production deployments
- Implement proper access controls for the management API
- Regularly rotate authentication credentials
- Monitor health check logs for security anomalies

## License

MIT License - see LICENSE file for details.