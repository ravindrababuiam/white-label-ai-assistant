<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  import type { MCPServerConfig } from '../mcp-manager.js';
  
  export let mcpManager: any;
  export let editingServer: MCPServerConfig | null = null;
  export let isOpen = false;
  
  const dispatch = createEventDispatcher();
  
  let formData: Partial<MCPServerConfig> = {
    id: '',
    name: '',
    endpoint: '',
    protocol: 'sse',
    enabled: true,
    autoConnect: true,
    authentication: {
      type: 'none'
    }
  };
  
  let errors: Record<string, string> = {};
  let isSubmitting = false;

  $: if (editingServer) {
    formData = { ...editingServer };
  } else {
    resetForm();
  }

  function resetForm() {
    formData = {
      id: '',
      name: '',
      endpoint: '',
      protocol: 'sse',
      enabled: true,
      autoConnect: true,
      authentication: {
        type: 'none'
      }
    };
    errors = {};
  }

  function validateForm(): boolean {
    errors = {};
    
    if (!formData.id?.trim()) {
      errors.id = 'Server ID is required';
    } else if (!/^[a-zA-Z0-9-_]+$/.test(formData.id)) {
      errors.id = 'Server ID can only contain letters, numbers, hyphens, and underscores';
    }
    
    if (!formData.name?.trim()) {
      errors.name = 'Server name is required';
    }
    
    if (!formData.endpoint?.trim()) {
      errors.endpoint = 'Endpoint is required';
    } else {
      try {
        new URL(formData.endpoint);
        
        // Validate protocol-specific endpoint formats
        if (formData.protocol === 'websocket') {
          if (!formData.endpoint.startsWith('ws://') && !formData.endpoint.startsWith('wss://')) {
            errors.endpoint = 'WebSocket endpoints must start with ws:// or wss://';
          }
        }
      } catch {
        if (formData.protocol !== 'stdio') {
          errors.endpoint = 'Please enter a valid URL';
        }
      }
    }
    
    if (formData.protocol === 'stdio' && !formData.command?.trim()) {
      errors.command = 'Command is required for stdio protocol';
    }
    
    // Validate authentication
    if (formData.authentication?.type === 'bearer' && !formData.authentication.token?.trim()) {
      errors.authToken = 'Token is required for bearer authentication';
    }
    
    if (formData.authentication?.type === 'api-key' && !formData.authentication.token?.trim()) {
      errors.authToken = 'API key is required for API key authentication';
    }
    
    if (formData.authentication?.type === 'basic') {
      if (!formData.authentication.username?.trim()) {
        errors.authUsername = 'Username is required for basic authentication';
      }
      if (!formData.authentication.password?.trim()) {
        errors.authPassword = 'Password is required for basic authentication';
      }
    }
    
    return Object.keys(errors).length === 0;
  }

  async function handleSubmit() {
    if (!validateForm()) {
      return;
    }
    
    try {
      isSubmitting = true;
      
      const serverConfig: MCPServerConfig = {
        id: formData.id!,
        name: formData.name!,
        endpoint: formData.endpoint!,
        protocol: formData.protocol!,
        enabled: formData.enabled!,
        autoConnect: formData.autoConnect,
        authentication: formData.authentication?.type === 'none' ? undefined : formData.authentication
      };
      
      // Add stdio-specific fields
      if (formData.protocol === 'stdio') {
        serverConfig.command = formData.command;
        serverConfig.args = formData.args;
        serverConfig.env = formData.env;
      }
      
      if (editingServer) {
        // Update existing server
        await mcpManager.removeServer(editingServer.id);
        await mcpManager.addServer(serverConfig);
        dispatch('server-updated', serverConfig);
      } else {
        // Add new server
        await mcpManager.addServer(serverConfig);
        dispatch('server-added', serverConfig);
      }
      
      closeForm();
    } catch (error) {
      errors.submit = error instanceof Error ? error.message : 'Failed to save server';
    } finally {
      isSubmitting = false;
    }
  }

  function closeForm() {
    isOpen = false;
    resetForm();
    dispatch('close');
  }

  function updateAuthenticationType(type: string) {
    formData.authentication = { type };
  }

  function addEnvironmentVariable() {
    if (!formData.env) {
      formData.env = {};
    }
    formData.env[''] = '';
  }

  function removeEnvironmentVariable(key: string) {
    if (formData.env) {
      delete formData.env[key];
      formData.env = { ...formData.env };
    }
  }

  function addArgument() {
    if (!formData.args) {
      formData.args = [];
    }
    formData.args = [...formData.args, ''];
  }

  function removeArgument(index: number) {
    if (formData.args) {
      formData.args = formData.args.filter((_, i) => i !== index);
    }
  }
</script>

{#if isOpen}
  <div class="modal-overlay" on:click={closeForm}>
    <div class="modal-content" on:click|stopPropagation>
      <div class="modal-header">
        <h3 class="modal-title">
          {editingServer ? 'Edit MCP Server' : 'Add MCP Server'}
        </h3>
        <button class="close-button" on:click={closeForm}>×</button>
      </div>

      <form on:submit|preventDefault={handleSubmit} class="server-form">
        <div class="form-section">
          <h4 class="section-title">Basic Information</h4>
          
          <div class="form-group">
            <label class="form-label" for="server-id">
              Server ID <span class="required">*</span>
            </label>
            <input
              id="server-id"
              type="text"
              bind:value={formData.id}
              class="form-input {errors.id ? 'error' : ''}"
              placeholder="unique-server-id"
              disabled={!!editingServer}
            />
            {#if errors.id}
              <p class="error-message">{errors.id}</p>
            {/if}
          </div>

          <div class="form-group">
            <label class="form-label" for="server-name">
              Server Name <span class="required">*</span>
            </label>
            <input
              id="server-name"
              type="text"
              bind:value={formData.name}
              class="form-input {errors.name ? 'error' : ''}"
              placeholder="My MCP Server"
            />
            {#if errors.name}
              <p class="error-message">{errors.name}</p>
            {/if}
          </div>

          <div class="form-group">
            <label class="form-label" for="protocol">
              Protocol <span class="required">*</span>
            </label>
            <select
              id="protocol"
              bind:value={formData.protocol}
              class="form-input"
            >
              <option value="sse">Server-Sent Events (SSE)</option>
              <option value="websocket">WebSocket</option>
              <option value="stdio">Standard I/O</option>
            </select>
          </div>

          <div class="form-group">
            <label class="form-label" for="endpoint">
              Endpoint <span class="required">*</span>
            </label>
            <input
              id="endpoint"
              type="text"
              bind:value={formData.endpoint}
              class="form-input {errors.endpoint ? 'error' : ''}"
              placeholder={formData.protocol === 'websocket' ? 'wss://api.example.com/mcp' : 
                          formData.protocol === 'stdio' ? 'stdio://local' : 
                          'https://api.example.com/mcp'}
            />
            {#if errors.endpoint}
              <p class="error-message">{errors.endpoint}</p>
            {/if}
          </div>
        </div>

        {#if formData.protocol === 'stdio'}
          <div class="form-section">
            <h4 class="section-title">Stdio Configuration</h4>
            
            <div class="form-group">
              <label class="form-label" for="command">
                Command <span class="required">*</span>
              </label>
              <input
                id="command"
                type="text"
                bind:value={formData.command}
                class="form-input {errors.command ? 'error' : ''}"
                placeholder="python"
              />
              {#if errors.command}
                <p class="error-message">{errors.command}</p>
              {/if}
            </div>

            <div class="form-group">
              <label class="form-label">Arguments</label>
              {#if formData.args && formData.args.length > 0}
                {#each formData.args as arg, index}
                  <div class="array-input">
                    <input
                      type="text"
                      bind:value={formData.args[index]}
                      class="form-input"
                      placeholder="Argument {index + 1}"
                    />
                    <button
                      type="button"
                      class="btn btn-sm btn-danger"
                      on:click={() => removeArgument(index)}
                    >
                      Remove
                    </button>
                  </div>
                {/each}
              {/if}
              <button
                type="button"
                class="btn btn-sm btn-outline"
                on:click={addArgument}
              >
                Add Argument
              </button>
            </div>

            <div class="form-group">
              <label class="form-label">Environment Variables</label>
              {#if formData.env && Object.keys(formData.env).length > 0}
                {#each Object.entries(formData.env) as [key, value]}
                  <div class="key-value-input">
                    <input
                      type="text"
                      bind:value={key}
                      class="form-input"
                      placeholder="Variable name"
                    />
                    <input
                      type="text"
                      bind:value={formData.env[key]}
                      class="form-input"
                      placeholder="Variable value"
                    />
                    <button
                      type="button"
                      class="btn btn-sm btn-danger"
                      on:click={() => removeEnvironmentVariable(key)}
                    >
                      Remove
                    </button>
                  </div>
                {/each}
              {/if}
              <button
                type="button"
                class="btn btn-sm btn-outline"
                on:click={addEnvironmentVariable}
              >
                Add Environment Variable
              </button>
            </div>
          </div>
        {/if}

        <div class="form-section">
          <h4 class="section-title">Authentication</h4>
          
          <div class="form-group">
            <label class="form-label">Authentication Type</label>
            <select
              bind:value={formData.authentication.type}
              on:change={(e) => updateAuthenticationType(e.target.value)}
              class="form-input"
            >
              <option value="none">None</option>
              <option value="bearer">Bearer Token</option>
              <option value="api-key">API Key</option>
              <option value="basic">Basic Authentication</option>
            </select>
          </div>

          {#if formData.authentication?.type === 'bearer'}
            <div class="form-group">
              <label class="form-label" for="auth-token">
                Bearer Token <span class="required">*</span>
              </label>
              <input
                id="auth-token"
                type="password"
                bind:value={formData.authentication.token}
                class="form-input {errors.authToken ? 'error' : ''}"
                placeholder="Enter bearer token"
              />
              {#if errors.authToken}
                <p class="error-message">{errors.authToken}</p>
              {/if}
            </div>
          {/if}

          {#if formData.authentication?.type === 'api-key'}
            <div class="form-group">
              <label class="form-label" for="api-key">
                API Key <span class="required">*</span>
              </label>
              <input
                id="api-key"
                type="password"
                bind:value={formData.authentication.token}
                class="form-input {errors.authToken ? 'error' : ''}"
                placeholder="Enter API key"
              />
              {#if errors.authToken}
                <p class="error-message">{errors.authToken}</p>
              {/if}
            </div>

            <div class="form-group">
              <label class="form-label" for="api-key-header">
                Header Name
              </label>
              <input
                id="api-key-header"
                type="text"
                bind:value={formData.authentication.header}
                class="form-input"
                placeholder="X-API-Key"
              />
            </div>
          {/if}

          {#if formData.authentication?.type === 'basic'}
            <div class="form-group">
              <label class="form-label" for="auth-username">
                Username <span class="required">*</span>
              </label>
              <input
                id="auth-username"
                type="text"
                bind:value={formData.authentication.username}
                class="form-input {errors.authUsername ? 'error' : ''}"
                placeholder="Enter username"
              />
              {#if errors.authUsername}
                <p class="error-message">{errors.authUsername}</p>
              {/if}
            </div>

            <div class="form-group">
              <label class="form-label" for="auth-password">
                Password <span class="required">*</span>
              </label>
              <input
                id="auth-password"
                type="password"
                bind:value={formData.authentication.password}
                class="form-input {errors.authPassword ? 'error' : ''}"
                placeholder="Enter password"
              />
              {#if errors.authPassword}
                <p class="error-message">{errors.authPassword}</p>
              {/if}
            </div>
          {/if}
        </div>

        <div class="form-section">
          <h4 class="section-title">Options</h4>
          
          <div class="form-group">
            <label class="checkbox-label">
              <input
                type="checkbox"
                bind:checked={formData.enabled}
              />
              <span>Enable server</span>
            </label>
          </div>

          <div class="form-group">
            <label class="checkbox-label">
              <input
                type="checkbox"
                bind:checked={formData.autoConnect}
              />
              <span>Auto-connect when enabled</span>
            </label>
          </div>
        </div>

        {#if errors.submit}
          <div class="error-banner">
            {errors.submit}
          </div>
        {/if}

        <div class="form-actions">
          <button
            type="button"
            class="btn btn-outline"
            on:click={closeForm}
            disabled={isSubmitting}
          >
            Cancel
          </button>
          <button
            type="submit"
            class="btn btn-primary"
            disabled={isSubmitting}
          >
            {isSubmitting ? 'Saving...' : editingServer ? 'Update Server' : 'Add Server'}
          </button>
        </div>
      </form>
    </div>
  </div>
{/if}

<style>
  .modal-overlay {
    @apply fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4;
  }

  .modal-content {
    @apply bg-white dark:bg-gray-800 rounded-lg shadow-xl max-w-2xl w-full max-h-screen overflow-y-auto;
  }

  .modal-header {
    @apply flex items-center justify-between p-6 border-b border-gray-200 dark:border-gray-700;
  }

  .modal-title {
    @apply text-lg font-semibold text-gray-900 dark:text-white;
  }

  .close-button {
    @apply text-gray-400 hover:text-gray-600 text-2xl font-bold;
  }

  .server-form {
    @apply p-6 space-y-6;
  }

  .form-section {
    @apply space-y-4;
  }

  .section-title {
    @apply text-md font-medium text-gray-900 dark:text-white border-b border-gray-200 pb-2;
  }

  .form-group {
    @apply space-y-1;
  }

  .form-label {
    @apply block text-sm font-medium text-gray-700 dark:text-gray-300;
  }

  .required {
    @apply text-red-500;
  }

  .form-input {
    @apply w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500;
  }

  .form-input.error {
    @apply border-red-500 focus:ring-red-500 focus:border-red-500;
  }

  .error-message {
    @apply text-red-600 text-sm;
  }

  .error-banner {
    @apply p-3 bg-red-50 border border-red-200 rounded-lg text-red-600 text-sm;
  }

  .checkbox-label {
    @apply flex items-center space-x-2 cursor-pointer;
  }

  .array-input {
    @apply flex space-x-2 items-center;
  }

  .key-value-input {
    @apply grid grid-cols-2 gap-2 items-center;
  }

  .form-actions {
    @apply flex justify-end space-x-3 pt-6 border-t border-gray-200;
  }

  .btn {
    @apply px-4 py-2 rounded text-sm font-medium transition-colors;
  }

  .btn-primary {
    @apply bg-blue-600 text-white hover:bg-blue-700 disabled:opacity-50;
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
</style>