import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { MCPServerRegistry } from '../registry.js';
import { MCPServerConfig } from '../types.js';

describe('MCPServerRegistry', () => {
  let registry: MCPServerRegistry;

  beforeEach(async () => {
    registry = new MCPServerRegistry();
    await registry.start();
  });

  afterEach(async () => {
    await registry.stop();
  });

  describe('registerServer', () => {
    it('should register a valid server', async () => {
      const config: MCPServerConfig = {
        id: 'test-server',
        name: 'Test Server',
        endpoint: 'https://api.example.com'
      };

      const result = await registry.registerServer(config, 'test-user');
      expect(result.valid).toBe(true);

      const registered = registry.getServer('test-server');
      expect(registered).toBeDefined();
      expect(registered?.config.name).toBe('Test Server');
      expect(registered?.registeredBy).toBe('test-user');
    });

    it('should reject duplicate server registration', async () => {
      const config: MCPServerConfig = {
        id: 'duplicate-server',
        name: 'Test Server',
        endpoint: 'https://api.example.com'
      };

      // Register first time
      await registry.registerServer(config, 'test-user');

      // Try to register again
      const result = await registry.registerServer(config, 'test-user');
      expect(result.valid).toBe(false);
      expect(result.errors.some(e => e.message.includes('already exists'))).toBe(true);
    });

    it('should reject invalid server configuration', async () => {
      const config: MCPServerConfig = {
        id: 'invalid server!', // Invalid ID
        name: 'Test Server',
        endpoint: 'not-a-url'
      };

      const result = await registry.registerServer(config, 'test-user');
      expect(result.valid).toBe(false);
      expect(result.errors.length).toBeGreaterThan(0);
    });
  });

  describe('updateServer', () => {
    it('should update an existing server', async () => {
      const config: MCPServerConfig = {
        id: 'update-server',
        name: 'Original Name',
        endpoint: 'https://api.example.com'
      };

      // Register server
      await registry.registerServer(config, 'test-user');

      // Update server
      const updatedConfig: MCPServerConfig = {
        ...config,
        name: 'Updated Name',
        description: 'Updated description'
      };

      const result = await registry.updateServer('update-server', updatedConfig, 'update-user');
      expect(result.valid).toBe(true);

      const updated = registry.getServer('update-server');
      expect(updated?.config.name).toBe('Updated Name');
      expect(updated?.config.description).toBe('Updated description');
      expect(updated?.registeredBy).toBe('update-user');
    });

    it('should reject update for non-existent server', async () => {
      const config: MCPServerConfig = {
        id: 'non-existent',
        name: 'Test Server',
        endpoint: 'https://api.example.com'
      };

      const result = await registry.updateServer('non-existent', config, 'test-user');
      expect(result.valid).toBe(false);
      expect(result.errors.some(e => e.message.includes('not found'))).toBe(true);
    });

    it('should reject ID change during update', async () => {
      const config: MCPServerConfig = {
        id: 'original-id',
        name: 'Test Server',
        endpoint: 'https://api.example.com'
      };

      await registry.registerServer(config, 'test-user');

      const updatedConfig: MCPServerConfig = {
        ...config,
        id: 'changed-id' // Trying to change ID
      };

      const result = await registry.updateServer('original-id', updatedConfig, 'test-user');
      expect(result.valid).toBe(false);
      expect(result.errors.some(e => e.message.includes('cannot be changed'))).toBe(true);
    });
  });

  describe('unregisterServer', () => {
    it('should unregister an existing server', async () => {
      const config: MCPServerConfig = {
        id: 'remove-server',
        name: 'Test Server',
        endpoint: 'https://api.example.com'
      };

      await registry.registerServer(config, 'test-user');
      
      const success = await registry.unregisterServer('remove-server');
      expect(success).toBe(true);

      const removed = registry.getServer('remove-server');
      expect(removed).toBeUndefined();
    });

    it('should return false for non-existent server', async () => {
      const success = await registry.unregisterServer('non-existent');
      expect(success).toBe(false);
    });
  });

  describe('listServers', () => {
    beforeEach(async () => {
      // Register test servers
      const servers: MCPServerConfig[] = [
        {
          id: 'server-1',
          name: 'Server 1',
          endpoint: 'https://api1.example.com',
          protocol: 'sse',
          enabled: true,
          tags: ['tag1', 'tag2']
        },
        {
          id: 'server-2',
          name: 'Server 2',
          endpoint: 'wss://api2.example.com/ws',
          protocol: 'websocket',
          enabled: false,
          tags: ['tag2', 'tag3']
        },
        {
          id: 'server-3',
          name: 'Server 3',
          endpoint: 'https://api3.example.com', // Changed from stdio://local to valid URL
          protocol: 'sse', // Changed from stdio to sse since we don't have command
          enabled: true,
          tags: ['tag1']
        }
      ];

      for (const server of servers) {
        const result = await registry.registerServer(server, 'test-user');
        if (!result.valid) {
          console.error('Failed to register server:', server.id, result.errors);
        }
      }
    });

    it('should list all servers', () => {
      const result = registry.listServers();
      expect(result.servers).toHaveLength(3);
      expect(result.total).toBe(3);
    });

    it('should filter by enabled status', () => {
      const result = registry.listServers({ enabled: true });
      expect(result.servers).toHaveLength(2);
      expect(result.servers.every(s => s.config.enabled === true)).toBe(true);
    });

    it('should filter by protocol', () => {
      const result = registry.listServers({ protocol: 'sse' });
      expect(result.servers).toHaveLength(2);
      expect(result.servers.every(s => s.config.protocol === 'sse')).toBe(true);
    });

    it('should filter by tags', () => {
      const result = registry.listServers({ tags: ['tag1'] });
      expect(result.servers).toHaveLength(2);
      expect(result.servers.every(s => s.config.tags?.includes('tag1'))).toBe(true);
    });

    it('should sort servers', () => {
      const result = registry.listServers({ sortBy: 'name', sortOrder: 'asc' });
      expect(result.servers[0]?.config.name).toBe('Server 1');
      expect(result.servers[1]?.config.name).toBe('Server 2');
      expect(result.servers[2]?.config.name).toBe('Server 3');
    });

    it('should paginate results', () => {
      const result = registry.listServers({ page: 1, limit: 2 });
      expect(result.servers).toHaveLength(2);
      expect(result.total).toBe(3);
      expect(result.page).toBe(1);
      expect(result.limit).toBe(2);
    });
  });

  describe('enableServer and disableServer', () => {
    beforeEach(async () => {
      const config: MCPServerConfig = {
        id: 'toggle-server',
        name: 'Toggle Server',
        endpoint: 'https://api.example.com',
        enabled: true
      };

      await registry.registerServer(config, 'test-user');
    });

    it('should disable a server', () => {
      const success = registry.disableServer('toggle-server');
      expect(success).toBe(true);

      const server = registry.getServer('toggle-server');
      expect(server?.config.enabled).toBe(false);
    });

    it('should enable a server', () => {
      // First disable
      registry.disableServer('toggle-server');
      
      // Then enable
      const success = registry.enableServer('toggle-server');
      expect(success).toBe(true);

      const server = registry.getServer('toggle-server');
      expect(server?.config.enabled).toBe(true);
    });

    it('should return false for non-existent server', () => {
      const enableResult = registry.enableServer('non-existent');
      const disableResult = registry.disableServer('non-existent');
      
      expect(enableResult).toBe(false);
      expect(disableResult).toBe(false);
    });
  });
});