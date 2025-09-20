export interface MCPServerConfig {
  id: string;
  name: string;
  description?: string;
  endpoint: string;
  protocol?: 'stdio' | 'sse' | 'websocket';
  command?: string;
  args?: string[];
  env?: Record<string, string>;
  authentication?: Authentication;
  enabled?: boolean;
  healthCheck?: HealthCheckConfig;
  timeout?: number;
  retryPolicy?: RetryPolicy;
  tags?: string[];
}

export interface Authentication {
  type: 'none' | 'bearer' | 'api-key' | 'basic';
  token?: string;
  username?: string;
  password?: string;
  header?: string;
}

export interface HealthCheckConfig {
  enabled?: boolean;
  interval?: number;
  timeout?: number;
  retries?: number;
}

export interface RetryPolicy {
  enabled?: boolean;
  maxRetries?: number;
  backoffMultiplier?: number;
  initialDelay?: number;
}

export interface MCPServerStatus {
  id: string;
  status: 'healthy' | 'unhealthy' | 'unknown' | 'disabled';
  lastCheck: Date;
  lastError?: string | undefined;
  uptime?: number | undefined;
  responseTime?: number | undefined;
}

export interface MCPServerMetrics {
  id: string;
  totalRequests: number;
  successfulRequests: number;
  failedRequests: number;
  averageResponseTime: number;
  lastRequestTime?: Date;
  uptimePercentage: number;
}

export interface MCPServerRegistration {
  config: MCPServerConfig;
  registeredAt: Date;
  registeredBy: string;
  version?: string | undefined;
}

export interface MCPServerListResponse {
  servers: MCPServerRegistration[];
  total: number;
  page?: number | undefined;
  limit?: number | undefined;
}

export interface MCPServerHealthResponse {
  server: MCPServerConfig;
  status: MCPServerStatus;
  metrics: MCPServerMetrics;
}