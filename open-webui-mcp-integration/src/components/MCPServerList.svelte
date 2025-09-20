<script lang="ts">
  import { onMount, createEventDispatcher } from 'svelte';
  import type { MCPServerConfig, MCPServerStatus } from '../mcp-manager.js';
  
  export let mcpManager: any;
  
  const dispatch = createEventDispatcher();
  
  let servers: Array<{ config: MCPServerConfig; status: MCPServerStatus }> = [];
  let loading = false;
  let error = '';

  onMount(() => {
    loadServers();
    
    // Listen for server events
    mcpManager.on('server:added', loadServers);
    mcpManager.on('server:removed', loadServers);
    mcpManager.on('server:status:updated', loadServers);
    mcpManager.on('server:connected', loadServers);
    mcpManager.on('server:disconnected', loadServers);
  });

  async function loadServers() {
    try {
      loading = true;
      error = '';
      
      const configs = mcpManager.getAllServerConfigs();
      const statuses = mcpManager.getAllServerStatus();
      
      servers = Array.from(configs.entries()).map(([id, config]) => ({
        config,
        status: statuses.get(id) || { id, connected: false }
      }));
    } catch (err) {
      error = err instanceof Error ? err.message : 'Failed to load servers';
    } finally {
      loading = false;
    }
  }

  async function toggleConnection(serverId: string, connected: boolean) {
    try {
      if (connected) {
        await mcpManager.disconnectServer(serverId);
      } else {
        await mcpManager.connectServer(serverId);
      }
    } catch (err) {
      error = err instanceof Error ? err.message : 'Connection failed';
    }
  }

  async function toggleEnabled(serverId: string, enabled: boolean) {
    try {
      if (enabled) {
        await mcpManager.disableServer(serverId);
      } else {
        await mcpManager.enableServer(serverId);
      }
    } catch (err) {
      error = err instanceof Error ? err.message : 'Failed to toggle server';
    }
  }

  function getStatusColor(status: MCPServerStatus): string {
    if (status.connected) return 'text-green-600';
    if (status.lastError) return 'text-red-600';
    return 'text-gray-500';
  }

  function getStatusText(status: MCPServerStatus): string {
    if (status.connected) return 'Connected';
    if (status.lastError) return 'Error';
    return 'Disconnected';
  }

  function formatLastConnected(date?: Date): string {
    if (!date) return 'Never';
    return new Intl.RelativeTimeFormat('en', { numeric: 'auto' }).format(
      Math.floor((date.getTime() - Date.now()) / (1000 * 60)),
      'minute'
    );
  }
</script>

<div class="mcp-server-list">
  <div class="header">
    <h3 class="text-lg font-semibold text-gray-900 dark:text-white">
      MCP Servers
    </h3>
    <button
      class="btn btn-primary btn-sm"
      on:click={() => dispatch('add-server')}
    >
      Add Server
    </button>
  </div>

  {#if loading}
    <div class="loading">
      <div class="spinner"></div>
      <span>Loading servers...</span>
    </div>
  {/if}

  {#if error}
    <div class="error">
      <span class="text-red-600">{error}</span>
      <button class="btn btn-sm" on:click={loadServers}>Retry</button>
    </div>
  {/if}

  {#if servers.length === 0 && !loading}
    <div class="empty-state">
      <p class="text-gray-500 dark:text-gray-400">
        No MCP servers configured. Add a server to get started.
      </p>
    </div>
  {/if}

  <div class="server-grid">
    {#each servers as { config, status } (config.id)}
      <div class="server-card">
        <div class="server-header">
          <div class="server-info">
            <h4 class="server-name">{config.name}</h4>
            <p class="server-id text-sm text-gray-500">{config.id}</p>
          </div>
          
          <div class="server-status">
            <span class="status-indicator {getStatusColor(status)}">
              ●
            </span>
            <span class="status-text {getStatusColor(status)}">
              {getStatusText(status)}
            </span>
          </div>
        </div>

        <div class="server-details">
          <div class="detail-row">
            <span class="label">Protocol:</span>
            <span class="value">{config.protocol.toUpperCase()}</span>
          </div>
          
          <div class="detail-row">
            <span class="label">Endpoint:</span>
            <span class="value truncate" title={config.endpoint}>
              {config.endpoint}
            </span>
          </div>
          
          {#if status.lastConnected}
            <div class="detail-row">
              <span class="label">Last Connected:</span>
              <span class="value">{formatLastConnected(status.lastConnected)}</span>
            </div>
          {/if}
          
          {#if status.lastError}
            <div class="detail-row">
              <span class="label">Error:</span>
              <span class="value text-red-600 text-sm" title={status.lastError}>
                {status.lastError}
              </span>
            </div>
          {/if}

          {#if status.serverInfo}
            <div class="detail-row">
              <span class="label">Server:</span>
              <span class="value">
                {status.serverInfo.name} v{status.serverInfo.version}
              </span>
            </div>
          {/if}
        </div>

        <div class="server-actions">
          <label class="toggle-switch">
            <input
              type="checkbox"
              checked={config.enabled}
              on:change={() => toggleEnabled(config.id, config.enabled)}
            />
            <span class="slider"></span>
            <span class="toggle-label">Enabled</span>
          </label>

          {#if config.enabled}
            <button
              class="btn btn-sm {status.connected ? 'btn-secondary' : 'btn-primary'}"
              on:click={() => toggleConnection(config.id, status.connected)}
            >
              {status.connected ? 'Disconnect' : 'Connect'}
            </button>
          {/if}

          <button
            class="btn btn-sm btn-outline"
            on:click={() => dispatch('edit-server', config.id)}
          >
            Edit
          </button>

          <button
            class="btn btn-sm btn-danger"
            on:click={() => dispatch('remove-server', config.id)}
          >
            Remove
          </button>
        </div>
      </div>
    {/each}
  </div>
</div>

<style>
  .mcp-server-list {
    @apply space-y-4;
  }

  .header {
    @apply flex items-center justify-between;
  }

  .loading {
    @apply flex items-center space-x-2 p-4 text-gray-600;
  }

  .spinner {
    @apply w-4 h-4 border-2 border-gray-300 border-t-blue-600 rounded-full animate-spin;
  }

  .error {
    @apply flex items-center justify-between p-3 bg-red-50 border border-red-200 rounded-lg;
  }

  .empty-state {
    @apply text-center p-8;
  }

  .server-grid {
    @apply grid gap-4 md:grid-cols-2 lg:grid-cols-3;
  }

  .server-card {
    @apply bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-4 space-y-3;
  }

  .server-header {
    @apply flex items-start justify-between;
  }

  .server-info {
    @apply flex-1;
  }

  .server-name {
    @apply font-medium text-gray-900 dark:text-white;
  }

  .server-status {
    @apply flex items-center space-x-1 text-sm;
  }

  .status-indicator {
    @apply text-lg leading-none;
  }

  .server-details {
    @apply space-y-2 text-sm;
  }

  .detail-row {
    @apply flex justify-between;
  }

  .label {
    @apply text-gray-500 dark:text-gray-400 font-medium;
  }

  .value {
    @apply text-gray-900 dark:text-white;
  }

  .server-actions {
    @apply flex items-center space-x-2 pt-2 border-t border-gray-100 dark:border-gray-700;
  }

  .toggle-switch {
    @apply flex items-center space-x-2 cursor-pointer;
  }

  .toggle-switch input {
    @apply sr-only;
  }

  .slider {
    @apply relative inline-block w-10 h-6 bg-gray-200 rounded-full transition-colors;
  }

  .slider::before {
    @apply absolute top-1 left-1 w-4 h-4 bg-white rounded-full transition-transform;
    content: '';
  }

  .toggle-switch input:checked + .slider {
    @apply bg-blue-600;
  }

  .toggle-switch input:checked + .slider::before {
    @apply transform translate-x-4;
  }

  .toggle-label {
    @apply text-sm text-gray-700 dark:text-gray-300;
  }

  .btn {
    @apply px-3 py-1 rounded text-sm font-medium transition-colors;
  }

  .btn-primary {
    @apply bg-blue-600 text-white hover:bg-blue-700;
  }

  .btn-secondary {
    @apply bg-gray-600 text-white hover:bg-gray-700;
  }

  .btn-outline {
    @apply border border-gray-300 text-gray-700 hover:bg-gray-50;
  }

  .btn-danger {
    @apply bg-red-600 text-white hover:bg-red-700;
  }

  .btn-sm {
    @apply px-2 py-1 text-xs;
  }

  .truncate {
    @apply overflow-hidden text-ellipsis whitespace-nowrap;
  }
</style>