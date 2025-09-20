import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { AgencyIntegrationManager } from '../src/agency-integration-manager.js';
import { AgencyMCPClient } from '../src/agency-mcp-client.js';
import * as fs from 'fs/promises';

// Mock dependencies
vi.mock('fs/promises');
vi.mock('../src/agency-mcp-client.js');

describe('AgencyIntegrationManager', () => {
  let manager: AgencyIntegrationManager;
  let mockConfig: any;

  beforeEach(() => {
    manager = new AgencyIntegrationManager();
    
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
        expectedTools: ['test_tool'],
        expectedResources: ['test_resource'],
        expectedPrompts: ['test_prompt']
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

    // Mock fs.readFile
    vi.mocked(fs.readFile).mockResolvedValue(JSON.stringify(mockConfig));
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('initialization', () => {
    it('should initialize successfully with valid configuration', async () => {
      const mockClient = {
        initialize: vi.fn().mockResolvedValue({}),
        listAgencyTools: vi.fn().mockResolvedValue([{ name: 'test_tool' }]),
        listAgencyResources: vi.fn().mockResolvedValue([{ uri: 'test_resource' }]),
        listAgencyPrompts: vi.fn().mockResolvedValue([{ name: 'test_prompt' }]),
        on: vi.fn(),
        disconnect: vi.fn()
      };

      vi.mocked(AgencyMCPClient).mockImplementation(() => mockClient as any);

      await manager.initialize();

      expect(AgencyMCPClient).toHaveBeenCalledWith(mockConfig);
      expect(mockClient.initialize).toHaveBeenCalled();
      
      const status = manager.getStatus();
      expect(status.connected).toBe(true);
      expect(status.authenticated).toBe(true);
    });

    it('should handle initialization errors', async () => {
      const mockClient = {
        initialize: vi.fn().mockRejectedValue(new Error('Connection failed')),
        on: vi.fn(),
        disconnect: vi.fn()
      };

      vi.mocked(AgencyMCPClient).mockImplementation(() => mockClient as any);

      await expect(manager.initialize()).rejects.toThrow('Connection failed');
      
      const status = manager.getStatus();
      expect(status.connected).toBe(false);
      expect(status.lastError).toBe('Connection failed');
    });

    it('should load configuration from custom path', async () => {
      const customConfig = { ...mockConfig, server: { ...mockConfig.server, id: 'custom-server' } };
      vi.mocked(fs.readFile).mockResolvedValue(JSON.stringify(customConfig));

      const mockClient = {
        initialize: vi.fn().mockResolvedValue({}),
        listAgencyTools: vi.fn().mockResolvedValue([]),
        listAgencyResources: vi.fn().mockResolvedValue([]),
        listAgencyPrompts: vi.fn().mockResolvedValue([]),
        on: vi.fn(),
        disconnect: vi.fn()
      };

      vi.mocked(AgencyMCPClient).mockImplementation(() => mockClient as any);

      await manager.initialize('/custom/config/path.json');

      expect(fs.readFile).toHaveBeenCalledWith('/custom/config/path.json', 'utf-8');
      expect(AgencyMCPClient).toHaveBeenCalledWith(customConfig);
    });
  });

  describe('tool execution', () => {
    beforeEach(async () => {
      const mockClient = {
        initialize: vi.fn().mockResolvedValue({}),
        listAgencyTools: vi.fn().mockResolvedValue([{ name: 'test_tool' }]),
        listAgencyResources: vi.fn().mockResolvedValue([]),
        listAgencyPrompts: vi.fn().mockResolvedValue([]),
        executeAgencyTool: vi.fn(),
        on: vi.fn(),
        disconnect: vi.fn()
      };

      vi.mocked(AgencyMCPClient).mockImplementation(() => mockClient as any);
      await manager.initialize();
    });

    it('should execute tool successfully', async () => {
      const mockClient = manager['client'] as any;
      mockClient.executeAgencyTool.mockResolvedValue({ result: 'success' });

      const request = {
        toolName: 'test_tool',
        arguments: { param1: 'value1' },
        context: { userId: 'user123' }
      };

      const response = await manager.executeTool(request);

      expect(mockClient.executeAgencyTool).toHaveBeenCalledWith(
        'test_tool',
        { param1: 'value1' },
        { userId: 'user123' }
      );
      
      expect(response.success).toBe(true);
      expect(response.result).toEqual({ result: 'success' });
      expect(response.duration).toBeGreaterThan(0);
    });

    it('should handle tool execution errors', async () => {
      const mockClient = manager['client'] as any;
      mockClient.executeAgencyTool.mockRejectedValue(new Error('Tool execution failed'));

      const request = {
        toolName: 'test_tool',
        arguments: { param1: 'value1' }
      };

      const response = await manager.executeTool(request);

      expect(response.success).toBe(false);
      expect(response.error).toBe('Tool execution failed');
      expect(response.duration).toBeGreaterThan(0);
    });

    it('should throw error when not connected', async () => {
      await manager.disconnect();

      const request = {
        toolName: 'test_tool',
        arguments: { param1: 'value1' }
      };

      await expect(manager.executeTool(request)).rejects.toThrow('Agency MCP client not connected');
    });
  });

  describe('resource operations', () => {
    beforeEach(async () => {
      const mockClient = {
        initialize: vi.fn().mockResolvedValue({}),
        listAgencyTools: vi.fn().mockResolvedValue([]),
        listAgencyResources: vi.fn().mockResolvedValue([{ uri: 'test://resource' }]),
        listAgencyPrompts: vi.fn().mockResolvedValue([]),
        readAgencyResource: vi.fn(),
        on: vi.fn(),
        disconnect: vi.fn()
      };

      vi.mocked(AgencyMCPClient).mockImplementation(() => mockClient as any);
      await manager.initialize();
    });

    it('should list available resources', async () => {
      const resources = await manager.listAvailableResources();
      
      expect(resources).toEqual([{ uri: 'test://resource' }]);
    });

    it('should read resource content', async () => {
      const mockClient = manager['client'] as any;
      mockClient.readAgencyResource.mockResolvedValue({ content: 'resource content' });

      const result = await manager.readResource('test://resource');

      expect(mockClient.readAgencyResource).toHaveBeenCalledWith('test://resource');
      expect(result).toEqual({ content: 'resource content' });
    });
  });

  describe('prompt operations', () => {
    beforeEach(async () => {
      const mockClient = {
        initialize: vi.fn().mockResolvedValue({}),
        listAgencyTools: vi.fn().mockResolvedValue([]),
        listAgencyResources: vi.fn().mockResolvedValue([]),
        listAgencyPrompts: vi.fn().mockResolvedValue([{ name: 'test_prompt' }]),
        getAgencyPrompt: vi.fn(),
        on: vi.fn(),
        disconnect: vi.fn()
      };

      vi.mocked(AgencyMCPClient).mockImplementation(() => mockClient as any);
      await manager.initialize();
    });

    it('should list available prompts', async () => {
      const prompts = await manager.listAvailablePrompts();
      
      expect(prompts).toEqual([{ name: 'test_prompt' }]);
    });

    it('should get prompt with arguments', async () => {
      const mockClient = manager['client'] as any;
      mockClient.getAgencyPrompt.mockResolvedValue({ 
        messages: [{ role: 'user', content: 'Test prompt' }] 
      });

      const result = await manager.getPrompt('test_prompt', { arg1: 'value1' });

      expect(mockClient.getAgencyPrompt).toHaveBeenCalledWith('test_prompt', { arg1: 'value1' });
      expect(result).toEqual({ 
        messages: [{ role: 'user', content: 'Test prompt' }] 
      });
    });
  });

  describe('health check', () => {
    it('should return true when healthy', async () => {
      const mockClient = {
        initialize: vi.fn().mockResolvedValue({}),
        listAgencyTools: vi.fn().mockResolvedValue([]),
        listAgencyResources: vi.fn().mockResolvedValue([]),
        listAgencyPrompts: vi.fn().mockResolvedValue([]),
        on: vi.fn(),
        disconnect: vi.fn()
      };

      vi.mocked(AgencyMCPClient).mockImplementation(() => mockClient as any);
      await manager.initialize();

      const isHealthy = await manager.healthCheck();
      expect(isHealthy).toBe(true);
    });

    it('should return false when not connected', async () => {
      const isHealthy = await manager.healthCheck();
      expect(isHealthy).toBe(false);
    });

    it('should return false when health check fails', async () => {
      const mockClient = {
        initialize: vi.fn().mockResolvedValue({}),
        listAgencyTools: vi.fn().mockRejectedValue(new Error('Health check failed')),
        listAgencyResources: vi.fn().mockResolvedValue([]),
        listAgencyPrompts: vi.fn().mockResolvedValue([]),
        on: vi.fn(),
        disconnect: vi.fn()
      };

      vi.mocked(AgencyMCPClient).mockImplementation(() => mockClient as any);
      await manager.initialize();

      const isHealthy = await manager.healthCheck();
      expect(isHealthy).toBe(false);
    });
  });

  describe('configuration validation', () => {
    it('should validate valid configuration', async () => {
      const result = await manager.validateConfiguration();
      
      expect(result.valid).toBe(true);
      expect(result.errors).toHaveLength(0);
    });

    it('should detect missing required fields', async () => {
      const invalidConfig = { ...mockConfig };
      delete invalidConfig.server.id;
      delete invalidConfig.server.endpoint;
      
      vi.mocked(fs.readFile).mockResolvedValue(JSON.stringify(invalidConfig));

      const result = await manager.validateConfiguration();
      
      expect(result.valid).toBe(false);
      expect(result.errors).toContain('Server ID is required');
      expect(result.errors).toContain('Server endpoint is required');
    });

    it('should detect invalid OAuth2 configuration', async () => {
      const invalidConfig = {
        ...mockConfig,
        authentication: {
          type: 'oauth2'
          // Missing required OAuth2 fields
        }
      };
      
      vi.mocked(fs.readFile).mockResolvedValue(JSON.stringify(invalidConfig));

      const result = await manager.validateConfiguration();
      
      expect(result.valid).toBe(false);
      expect(result.errors).toContain('Token endpoint is required for OAuth2 authentication');
      expect(result.errors).toContain('Client ID is required for OAuth2 authentication');
      expect(result.errors).toContain('Client secret is required for OAuth2 authentication');
    });

    it('should handle configuration file errors', async () => {
      vi.mocked(fs.readFile).mockRejectedValue(new Error('File not found'));

      const result = await manager.validateConfiguration();
      
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Configuration validation failed');
    });
  });

  describe('event handling', () => {
    it('should emit events for tool execution', async () => {
      const mockClient = {
        initialize: vi.fn().mockResolvedValue({}),
        listAgencyTools: vi.fn().mockResolvedValue([]),
        listAgencyResources: vi.fn().mockResolvedValue([]),
        listAgencyPrompts: vi.fn().mockResolvedValue([]),
        executeAgencyTool: vi.fn().mockResolvedValue({ result: 'success' }),
        on: vi.fn(),
        disconnect: vi.fn()
      };

      vi.mocked(AgencyMCPClient).mockImplementation(() => mockClient as any);
      await manager.initialize();

      const toolExecutedSpy = vi.fn();
      manager.on('tool-executed', toolExecutedSpy);

      const request = {
        toolName: 'test_tool',
        arguments: { param1: 'value1' }
      };

      await manager.executeTool(request);

      expect(toolExecutedSpy).toHaveBeenCalled();
    });

    it('should emit events for connection status changes', async () => {
      const connectedSpy = vi.fn();
      const disconnectedSpy = vi.fn();
      
      manager.on('connected', connectedSpy);
      manager.on('disconnected', disconnectedSpy);

      const mockClient = {
        initialize: vi.fn().mockResolvedValue({}),
        listAgencyTools: vi.fn().mockResolvedValue([]),
        listAgencyResources: vi.fn().mockResolvedValue([]),
        listAgencyPrompts: vi.fn().mockResolvedValue([]),
        on: vi.fn(),
        disconnect: vi.fn()
      };

      vi.mocked(AgencyMCPClient).mockImplementation(() => mockClient as any);
      
      await manager.initialize();
      expect(connectedSpy).toHaveBeenCalled();

      await manager.disconnect();
      expect(disconnectedSpy).toHaveBeenCalled();
    });
  });
});