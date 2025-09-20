import { describe, it, expect, beforeEach } from 'vitest';
import { MCPConfigValidator } from '../config-validator.js';
import { MCPServerConfig } from '../types.js';

describe('MCPConfigValidator', () => {
  let validator: MCPConfigValidator;

  beforeEach(() => {
    validator = new MCPConfigValidator();
  });

  describe('validateServerConfig', () => {
    it('should validate a valid server configuration', () => {
      const config: MCPServerConfig = {
        id: 'test-server',
        name: 'Test Server',
        endpoint: 'https://api.example.com',
        protocol: 'sse',
        enabled: true
      };

      const result = validator.validateServerConfig(config);
      expect(result.valid).toBe(true);
      expect(result.errors).toHaveLength(0);
    });

    it('should reject configuration with invalid ID format', () => {
      const config: MCPServerConfig = {
        id: 'test server!', // Invalid characters
        name: 'Test Server',
        endpoint: 'https://api.example.com'
      };

      const result = validator.validateServerConfig(config);
      expect(result.valid).toBe(false);
      expect(result.errors.length).toBeGreaterThan(0);
    });

    it('should reject configuration with invalid endpoint', () => {
      const config: MCPServerConfig = {
        id: 'test-server',
        name: 'Test Server',
        endpoint: 'not-a-url'
      };

      const result = validator.validateServerConfig(config);
      expect(result.valid).toBe(false);
      expect(result.errors.length).toBeGreaterThan(0);
    });

    it('should validate stdio protocol with command', () => {
      const config: MCPServerConfig = {
        id: 'stdio-server',
        name: 'Stdio Server',
        endpoint: 'stdio://local',
        protocol: 'stdio',
        command: 'python',
        args: ['-m', 'mcp_server']
      };

      const result = validator.validateServerConfig(config);
      expect(result.valid).toBe(true);
    });

    it('should reject stdio protocol without command', () => {
      const config: MCPServerConfig = {
        id: 'stdio-server',
        name: 'Stdio Server',
        endpoint: 'stdio://local',
        protocol: 'stdio'
      };

      const result = validator.validateServerConfig(config);
      expect(result.valid).toBe(false);
      expect(result.errors.some(e => e.field === 'command')).toBe(true);
    });

    it('should validate bearer authentication', () => {
      const config: MCPServerConfig = {
        id: 'auth-server',
        name: 'Auth Server',
        endpoint: 'https://api.example.com',
        authentication: {
          type: 'bearer',
          token: 'test-token'
        }
      };

      const result = validator.validateServerConfig(config);
      expect(result.valid).toBe(true);
    });

    it('should reject bearer authentication without token', () => {
      const config: MCPServerConfig = {
        id: 'auth-server',
        name: 'Auth Server',
        endpoint: 'https://api.example.com',
        authentication: {
          type: 'bearer'
        }
      };

      const result = validator.validateServerConfig(config);
      expect(result.valid).toBe(false);
      expect(result.errors.some(e => e.field === 'authentication.token')).toBe(true);
    });

    it('should validate websocket endpoint format', () => {
      const config: MCPServerConfig = {
        id: 'ws-server',
        name: 'WebSocket Server',
        endpoint: 'wss://api.example.com/ws',
        protocol: 'websocket'
      };

      const result = validator.validateServerConfig(config);
      expect(result.valid).toBe(true);
    });

    it('should reject invalid websocket endpoint format', () => {
      const config: MCPServerConfig = {
        id: 'ws-server',
        name: 'WebSocket Server',
        endpoint: 'https://api.example.com',
        protocol: 'websocket'
      };

      const result = validator.validateServerConfig(config);
      expect(result.valid).toBe(false);
      expect(result.errors.some(e => e.field === 'endpoint')).toBe(true);
    });
  });

  describe('validateServerList', () => {
    it('should validate a list of unique servers', () => {
      const configs: MCPServerConfig[] = [
        {
          id: 'server-1',
          name: 'Server 1',
          endpoint: 'https://api1.example.com'
        },
        {
          id: 'server-2',
          name: 'Server 2',
          endpoint: 'https://api2.example.com'
        }
      ];

      const result = validator.validateServerList(configs);
      expect(result.valid).toBe(true);
    });

    it('should reject list with duplicate server IDs', () => {
      const configs: MCPServerConfig[] = [
        {
          id: 'duplicate-id',
          name: 'Server 1',
          endpoint: 'https://api1.example.com'
        },
        {
          id: 'duplicate-id',
          name: 'Server 2',
          endpoint: 'https://api2.example.com'
        }
      ];

      const result = validator.validateServerList(configs);
      expect(result.valid).toBe(false);
      expect(result.errors.some(e => e.message.includes('Duplicate server ID'))).toBe(true);
    });
  });
});