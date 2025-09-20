import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { AgencyMCPClient } from '../src/agency-mcp-client.js';
import { MCPClient } from '../../open-webui-mcp-integration/src/mcp-client.js';

// Mock dependencies
vi.mock('../../open-webui-mcp-integration/src/mcp-client.js');

// Mock fetch globally
global.fetch = vi.fn();

describe('AgencyMCPClient', () => {
  let client: AgencyMCPClient;
  let mockConfig: any;
  let mockMCPClient: any;

  beforeEach(() => {
    mockConfig = {
      server: {
        id: 'test-agency-server',
        name: 'Test Agency Server',
        description: 'Test server',
        endpoint: 'https://test-agency.example.com/mcp',
        protocol: 'sse',
        enabled: true,
        autoConnect: true,
        timeout: 30000,
        retryPolicy: {
          enabled: true,
          maxRetries: 3,
          backoffMultiplier: 2,
          initialDelay: 1000
        },
        healthCheck: {
          enabled: true,
          interval: 30000,
          timeout: 5000,
          retries: 3
        },
        tags: ['test', 'agency']
      },
      authentication: {
        type: 'bearer',
        token: 'test-token'
      },
      capabilities: {
        expectedTools: ['file_operations', 'web_search'],
        expectedResources: ['project_files'],
        expectedPrompts: ['code_review']
      },
      security: {
        allowedOrigins: ['https://test.example.com'],
        requiredScopes: ['mcp:tools:execute'],
        rateLimiting: {
          enabled: true,
          requestsPerMinute: 100,
          burstLimit: 20
        }
      },
      monitoring: {
        enableDetailedLogging: true,
        logLevel: 'INFO'
      }
    };

    mockMCPClient = {
      connect: vi.fn().mockResolvedValue(undefined),
      disconnect: vi.fn().mockResolvedValue(undefined),
      initialize: vi.fn().mockResolvedValue({
        name: 'Test Agency Server',
        version: '1.0.0',
        capabilities: {}
      }),
      listTools: vi.fn().mockResolvedValue([
        { name: 'file_operations', description: 'File operations tool' },
        { name: 'web_search', description: 'Web search tool' }
      ]),
      listResources: vi.fn().mockResolvedValue([
        { uri: 'file://project_files', name: 'Project Files' }
      ]),
      listPrompts: vi.fn().mockResolvedValue([
        { name: 'code_review', description: 'Code review prompt' }
      ]),
      callTool: vi.fn(),
      readResource: vi.fn(),
      getPrompt: vi.fn(),
      on: vi.fn(),
      emit: vi.fn()
    };

    vi.mocked(MCPClient).mockImplementation(() => mockMCPClient);

    client = new AgencyMCPClient(mockConfig);
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('initialization', () => {
    it('should initialize successfully with bearer authentication', async () => {
      await client.initialize();

      expect(mockMCPClient.connect).toHaveBeenCalledWith({
        type: 'bearer',
        token: 'test-token'
      });
      expect(mockMCPClient.initialize).toHaveBeenCalledWith({
        roots: { listChanged: true },
        sampling: {}
      });
    });

    it('should handle OAuth2 authentication', async () => {
      const oauthConfig = {
        ...mockConfig,
        authentication: {
          type: 'oauth2',
          tokenEndpoint: 'https://auth.example.com/token',
          clientId: 'test-client-id',
          clientSecret: 'test-client-secret'
        }
      };

      // Mock successful OAuth2 response
      vi.mocked(fetch).mockResolvedValue({
        ok: true,
        json: () => Promise.resolve({
          access_token: 'oauth-access-token',
          expires_in: 3600
        })
      } as Response);

      const oauthClient = new AgencyMCPClient(oauthConfig);
      await oauthClient.initialize();

      expect(fetch).toHaveBeenCalledWith('https://auth.example.com/token', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': expect.stringContaining('Basic ')
        },
        body: expect.any(URLSearchParams)
      });

      expect(mockMCPClient.connect).toHaveBeenCalledWith({
        type: 'bearer',
        token: 'oauth-access-token'
      });
    });

    it('should handle OAuth2 authentication failure', async () => {
      const oauthConfig = {
        ...mockConfig,
        authentication: {
          type: 'oauth2',
          tokenEndpoint: 'https://auth.example.com/token',
          clientId: 'test-client-id',
          clientSecret: 'test-client-secret'
        }
      };

      // Mock failed OAuth2 response
      vi.mocked(fetch).mockResolvedValue({
        ok: false,
        status: 401,
        statusText: 'Unauthorized'
      } as Response);

      const oauthClient = new AgencyMCPClient(oauthConfig);
      
      await expect(oauthClient.initialize()).rejects.toThrow('OAuth2 token request failed: 401 Unauthorized');
    });

    it('should validate server capabilities', async () => {
      const capabilityWarningSpy = vi.fn();
      client.on('capability-warning', capabilityWarningSpy);

      // Mock missing expected tools
      mockMCPClient.listTools.mockResolvedValue([
        { name: 'file_operations', description: 'File operations tool' }
        // Missing 'web_search' tool
      ]);

      await client.initialize();

      expect(capabilityWarningSpy).toHaveBeenCalledWith({
        type: 'tools',
        missing: ['web_search']
      });
    });
  });

  describe('tool execution', () => {
    beforeEach(async () => {
      await client.initialize();
    });

    it('should execute tool successfully', async () => {
      mockMCPClient.callTool.mockResolvedValue({ result: 'success' });

      const result = await client.executeAgencyTool('file_operations', {
        action: 'read',
        path: '/test/file.txt'
      });

      expect(mockMCPClient.callTool).toHaveBeenCalledWith('file_operations', {
        action: 'read',
        path: '/test/file.txt'
      });
      expect(result).toEqual({ result: 'success' });
    });

    it('should handle tool execution errors', async () => {
      mockMCPClient.callTool.mockRejectedValue(new Error('Tool execution failed'));

      await expect(client.executeAgencyTool('file_operations', {}))
        .rejects.toThrow('Tool execution failed');
    });

    it('should track execution metrics', async () => {
      mockMCPClient.callTool.mockResolvedValue({ result: 'success' });

      await client.executeAgencyTool('file_operations', {});

      const metrics = client.getMetrics();
      expect(metrics.totalRequests).toBe(1);
      expect(metrics.successfulRequests).toBe(1);
      expect(metrics.failedRequests).toBe(0);
    });

    it('should enforce rate limiting', async () => {
      mockMCPClient.callTool.mockResolvedValue({ result: 'success' });

      // Execute requests up to the limit
      for (let i = 0; i < 100; i++) {
        await client.executeAgencyTool('file_operations', {}, { userId: 'test-user' });
      }

      // Next request should be rate limited
      await expect(client.executeAgencyTool('file_operations', {}, { userId: 'test-user' }))
        .rejects.toThrow('Rate limit exceeded');

      const metrics = client.getMetrics();
      expect(metrics.rateLimitHits).toBe(1);
    });

    it('should allow different users to have separate rate limits', async () => {
      mockMCPClient.callTool.mockResolvedValue({ result: 'success' });

      // Execute requests for user1 up to the limit
      for (let i = 0; i < 100; i++) {
        await client.executeAgencyTool('file_operations', {}, { userId: 'user1' });
      }

      // user2 should still be able to make requests
      await expect(client.executeAgencyTool('file_operations', {}, { userId: 'user2' }))
        .resolves.toEqual({ result: 'success' });
    });
  });

  describe('resource operations', () => {
    beforeEach(async () => {
      await client.initialize();
    });

    it('should list resources', async () => {
      const resources = await client.listAgencyResources();
      
      expect(mockMCPClient.listResources).toHaveBeenCalled();
      expect(resources).toEqual([
        { uri: 'file://project_files', name: 'Project Files' }
      ]);
    });

    it('should read resource content', async () => {
      mockMCPClient.readResource.mockResolvedValue({ content: 'file content' });

      const result = await client.readAgencyResource('file://project_files/test.txt');

      expect(mockMCPClient.readResource).toHaveBeenCalledWith('file://project_files/test.txt');
      expect(result).toEqual({ content: 'file content' });
    });
  });

  describe('prompt operations', () => {
    beforeEach(async () => {
      await client.initialize();
    });

    it('should list prompts', async () => {
      const prompts = await client.listAgencyPrompts();
      
      expect(mockMCPClient.listPrompts).toHaveBeenCalled();
      expect(prompts).toEqual([
        { name: 'code_review', description: 'Code review prompt' }
      ]);
    });

    it('should get prompt with arguments', async () => {
      mockMCPClient.getPrompt.mockResolvedValue({
        messages: [{ role: 'user', content: 'Review this code' }]
      });

      const result = await client.getAgencyPrompt('code_review', { 
        language: 'typescript',
        file: 'test.ts'
      });

      expect(mockMCPClient.getPrompt).toHaveBeenCalledWith('code_review', {
        language: 'typescript',
        file: 'test.ts'
      });
      expect(result).toEqual({
        messages: [{ role: 'user', content: 'Review this code' }]
      });
    });
  });

  describe('token management', () => {
    it('should refresh expired OAuth2 tokens', async () => {
      const oauthConfig = {
        ...mockConfig,
        authentication: {
          type: 'oauth2',
          tokenEndpoint: 'https://auth.example.com/token',
          clientId: 'test-client-id',
          clientSecret: 'test-client-secret'
        }
      };

      // Mock initial OAuth2 response with short expiry
      vi.mocked(fetch).mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({
          access_token: 'initial-token',
          expires_in: 1 // 1 second expiry
        })
      } as Response);

      const oauthClient = new AgencyMCPClient(oauthConfig);
      await oauthClient.initialize();

      // Wait for token to expire
      await new Promise(resolve => setTimeout(resolve, 1100));

      // Mock refresh token response
      vi.mocked(fetch).mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({
          access_token: 'refreshed-token',
          expires_in: 3600
        })
      } as Response);

      // Execute tool should trigger token refresh
      mockMCPClient.callTool.mockResolvedValue({ result: 'success' });
      await oauthClient.executeAgencyTool('test_tool', {});

      // Should have made two token requests (initial + refresh)
      expect(fetch).toHaveBeenCalledTimes(2);
    });
  });

  describe('monitoring and logging', () => {
    beforeEach(async () => {
      await client.initialize();
    });

    it('should log tool executions when detailed logging is enabled', async () => {
      const configWithLogging = {
        ...mockConfig,
        monitoring: {
          ...mockConfig.monitoring,
          logsEndpoint: 'https://logs.example.com/api/logs'
        }
      };

      const loggingClient = new AgencyMCPClient(configWithLogging);
      await loggingClient.initialize();

      // Mock successful log request
      vi.mocked(fetch).mockResolvedValue({
        ok: true
      } as Response);

      mockMCPClient.callTool.mockResolvedValue({ result: 'success' });
      await loggingClient.executeAgencyTool('test_tool', {}, { userId: 'test-user' });

      expect(fetch).toHaveBeenCalledWith('https://logs.example.com/api/logs', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer test-token'
        },
        body: expect.stringContaining('"toolName":"test_tool"')
      });
    });

    it('should handle logging failures gracefully', async () => {
      const configWithLogging = {
        ...mockConfig,
        monitoring: {
          ...mockConfig.monitoring,
          logsEndpoint: 'https://logs.example.com/api/logs'
        }
      };

      const loggingClient = new AgencyMCPClient(configWithLogging);
      await loggingClient.initialize();

      // Mock failed log request
      vi.mocked(fetch).mockRejectedValue(new Error('Logging failed'));

      mockMCPClient.callTool.mockResolvedValue({ result: 'success' });
      
      // Should not throw error even if logging fails
      await expect(loggingClient.executeAgencyTool('test_tool', {}))
        .resolves.toEqual({ result: 'success' });
    });
  });

  describe('error handling', () => {
    it('should handle connection errors', async () => {
      mockMCPClient.connect.mockRejectedValue(new Error('Connection failed'));

      await expect(client.initialize()).rejects.toThrow('Connection failed');
    });

    it('should handle authentication errors', async () => {
      const invalidConfig = {
        ...mockConfig,
        authentication: {
          type: 'bearer'
          // Missing token
        }
      };

      const invalidClient = new AgencyMCPClient(invalidConfig);
      
      await expect(invalidClient.initialize()).rejects.toThrow('Invalid authentication configuration');
    });

    it('should handle tool execution when not initialized', async () => {
      await expect(client.executeAgencyTool('test_tool', {}))
        .rejects.toThrow('Agency MCP client not initialized');
    });
  });
});