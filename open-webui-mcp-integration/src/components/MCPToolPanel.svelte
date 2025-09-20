<script lang="ts">
  import { onMount, createEventDispatcher } from 'svelte';
  import type { MCPTool, MCPToolExecution } from '../mcp-manager.js';
  
  export let mcpManager: any;
  
  const dispatch = createEventDispatcher();
  
  let tools: Array<MCPTool & { serverId: string }> = [];
  let selectedTool: (MCPTool & { serverId: string }) | null = null;
  let toolArguments: Record<string, any> = {};
  let executionResult: any = null;
  let executionError: string = '';
  let isExecuting = false;
  let loading = false;
  let searchQuery = '';
  let selectedServer = '';
  let executionHistory: MCPToolExecution[] = [];

  $: filteredTools = tools.filter(tool => {
    const matchesSearch = !searchQuery || 
      tool.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
      tool.description.toLowerCase().includes(searchQuery.toLowerCase());
    
    const matchesServer = !selectedServer || tool.serverId === selectedServer;
    
    return matchesSearch && matchesServer;
  });

  $: availableServers = [...new Set(tools.map(tool => tool.serverId))];

  onMount(() => {
    loadTools();
    loadExecutionHistory();
    
    // Listen for tool execution events
    mcpManager.on('tool:executed', handleToolExecuted);
    mcpManager.on('tool:error', handleToolError);
    mcpManager.on('server:connected', loadTools);
    mcpManager.on('server:disconnected', loadTools);
  });

  async function loadTools() {
    try {
      loading = true;
      tools = await mcpManager.listAvailableTools();
    } catch (error) {
      console.error('Failed to load tools:', error);
    } finally {
      loading = false;
    }
  }

  function loadExecutionHistory() {
    executionHistory = mcpManager.getToolExecutionHistory(10);
  }

  function selectTool(tool: MCPTool & { serverId: string }) {
    selectedTool = tool;
    toolArguments = {};
    executionResult = null;
    executionError = '';
    
    // Initialize arguments with default values
    if (tool.inputSchema?.properties) {
      for (const [key, schema] of Object.entries(tool.inputSchema.properties)) {
        if (typeof schema === 'object' && schema !== null && 'default' in schema) {
          toolArguments[key] = schema.default;
        }
      }
    }
  }

  async function executeTool() {
    if (!selectedTool) return;
    
    try {
      isExecuting = true;
      executionError = '';
      executionResult = null;
      
      const result = await mcpManager.executeTool(
        selectedTool.serverId,
        selectedTool.name,
        toolArguments
      );
      
      executionResult = result;
      loadExecutionHistory();
    } catch (error) {
      executionError = error instanceof Error ? error.message : String(error);
    } finally {
      isExecuting = false;
    }
  }

  function handleToolExecuted(execution: MCPToolExecution) {
    loadExecutionHistory();
    dispatch('tool-executed', execution);
  }

  function handleToolError(execution: MCPToolExecution) {
    loadExecutionHistory();
    dispatch('tool-error', execution);
  }

  function clearResults() {
    executionResult = null;
    executionError = '';
  }

  function formatExecutionTime(execution: MCPToolExecution): string {
    const now = new Date();
    const diff = now.getTime() - execution.timestamp.getTime();
    const minutes = Math.floor(diff / 60000);
    const seconds = Math.floor((diff % 60000) / 1000);
    
    if (minutes > 0) {
      return `${minutes}m ${seconds}s ago`;
    }
    return `${seconds}s ago`;
  }

  function getArgumentType(schema: any): string {
    if (schema.type === 'string') {
      if (schema.enum) return 'select';
      if (schema.format === 'textarea') return 'textarea';
      return 'text';
    }
    if (schema.type === 'number' || schema.type === 'integer') return 'number';
    if (schema.type === 'boolean') return 'checkbox';
    return 'text';
  }
</script>

<div class="mcp-tool-panel">
  <div class="panel-header">
    <h3 class="text-lg font-semibold text-gray-900 dark:text-white">
      MCP Tools
    </h3>
    <button
      class="btn btn-sm btn-outline"
      on:click={loadTools}
      disabled={loading}
    >
      {loading ? 'Loading...' : 'Refresh'}
    </button>
  </div>

  <div class="filters">
    <input
      type="text"
      placeholder="Search tools..."
      bind:value={searchQuery}
      class="search-input"
    />
    
    <select bind:value={selectedServer} class="server-filter">
      <option value="">All Servers</option>
      {#each availableServers as serverId}
        <option value={serverId}>{serverId}</option>
      {/each}
    </select>
  </div>

  <div class="panel-content">
    <div class="tools-section">
      <h4 class="section-title">Available Tools ({filteredTools.length})</h4>
      
      {#if loading}
        <div class="loading">
          <div class="spinner"></div>
          <span>Loading tools...</span>
        </div>
      {:else if filteredTools.length === 0}
        <div class="empty-state">
          <p class="text-gray-500">No tools available. Make sure MCP servers are connected.</p>
        </div>
      {:else}
        <div class="tools-grid">
          {#each filteredTools as tool}
            <div 
              class="tool-card {selectedTool?.name === tool.name && selectedTool?.serverId === tool.serverId ? 'selected' : ''}"
              on:click={() => selectTool(tool)}
            >
              <div class="tool-header">
                <h5 class="tool-name">{tool.name}</h5>
                <span class="server-badge">{tool.serverId}</span>
              </div>
              <p class="tool-description">{tool.description}</p>
              
              {#if tool.inputSchema?.properties}
                <div class="tool-params">
                  <span class="params-count">
                    {Object.keys(tool.inputSchema.properties).length} parameters
                  </span>
                </div>
              {/if}
            </div>
          {/each}
        </div>
      {/if}
    </div>

    {#if selectedTool}
      <div class="execution-section">
        <h4 class="section-title">Execute Tool: {selectedTool.name}</h4>
        
        <div class="tool-form">
          {#if selectedTool.inputSchema?.properties}
            <div class="arguments-form">
              {#each Object.entries(selectedTool.inputSchema.properties) as [key, schema]}
                <div class="form-group">
                  <label class="form-label">
                    {key}
                    {#if selectedTool.inputSchema.required?.includes(key)}
                      <span class="required">*</span>
                    {/if}
                  </label>
                  
                  {#if schema.description}
                    <p class="form-help">{schema.description}</p>
                  {/if}
                  
                  {#if getArgumentType(schema) === 'select'}
                    <select bind:value={toolArguments[key]} class="form-input">
                      {#each schema.enum as option}
                        <option value={option}>{option}</option>
                      {/each}
                    </select>
                  {:else if getArgumentType(schema) === 'textarea'}
                    <textarea
                      bind:value={toolArguments[key]}
                      class="form-input"
                      rows="3"
                      placeholder={schema.description || ''}
                    ></textarea>
                  {:else if getArgumentType(schema) === 'checkbox'}
                    <label class="checkbox-label">
                      <input
                        type="checkbox"
                        bind:checked={toolArguments[key]}
                      />
                      <span>Enable</span>
                    </label>
                  {:else}
                    <input
                      type={getArgumentType(schema)}
                      bind:value={toolArguments[key]}
                      class="form-input"
                      placeholder={schema.description || ''}
                    />
                  {/if}
                </div>
              {/each}
            </div>
          {:else}
            <p class="text-gray-500">This tool requires no parameters.</p>
          {/if}

          <div class="form-actions">
            <button
              class="btn btn-primary"
              on:click={executeTool}
              disabled={isExecuting}
            >
              {isExecuting ? 'Executing...' : 'Execute Tool'}
            </button>
            
            {#if executionResult || executionError}
              <button
                class="btn btn-outline"
                on:click={clearResults}
              >
                Clear Results
              </button>
            {/if}
          </div>
        </div>

        {#if executionResult}
          <div class="execution-result success">
            <h5 class="result-title">Execution Result</h5>
            <pre class="result-content">{JSON.stringify(executionResult, null, 2)}</pre>
          </div>
        {/if}

        {#if executionError}
          <div class="execution-result error">
            <h5 class="result-title">Execution Error</h5>
            <p class="error-message">{executionError}</p>
          </div>
        {/if}
      </div>
    {/if}

    <div class="history-section">
      <h4 class="section-title">Recent Executions</h4>
      
      {#if executionHistory.length === 0}
        <p class="text-gray-500">No recent executions.</p>
      {:else}
        <div class="history-list">
          {#each executionHistory as execution}
            <div class="history-item {execution.error ? 'error' : 'success'}">
              <div class="history-header">
                <span class="tool-name">{execution.toolName}</span>
                <span class="server-name">({execution.serverId})</span>
                <span class="execution-time">{formatExecutionTime(execution)}</span>
              </div>
              
              {#if execution.duration}
                <div class="execution-duration">
                  Completed in {execution.duration}ms
                </div>
              {/if}
              
              {#if execution.error}
                <div class="error-message">{execution.error}</div>
              {/if}
            </div>
          {/each}
        </div>
      {/if}
    </div>
  </div>
</div>

<style>
  .mcp-tool-panel {
    @apply space-y-4;
  }

  .panel-header {
    @apply flex items-center justify-between;
  }

  .filters {
    @apply flex space-x-3;
  }

  .search-input, .server-filter {
    @apply px-3 py-2 border border-gray-300 rounded-lg text-sm;
  }

  .search-input {
    @apply flex-1;
  }

  .server-filter {
    @apply min-w-32;
  }

  .panel-content {
    @apply space-y-6;
  }

  .section-title {
    @apply text-md font-medium text-gray-900 dark:text-white mb-3;
  }

  .loading {
    @apply flex items-center space-x-2 p-4 text-gray-600;
  }

  .spinner {
    @apply w-4 h-4 border-2 border-gray-300 border-t-blue-600 rounded-full animate-spin;
  }

  .empty-state {
    @apply text-center p-6;
  }

  .tools-grid {
    @apply grid gap-3 md:grid-cols-2;
  }

  .tool-card {
    @apply p-3 border border-gray-200 rounded-lg cursor-pointer hover:bg-gray-50 transition-colors;
  }

  .tool-card.selected {
    @apply border-blue-500 bg-blue-50;
  }

  .tool-header {
    @apply flex items-center justify-between mb-2;
  }

  .tool-name {
    @apply font-medium text-gray-900;
  }

  .server-badge {
    @apply px-2 py-1 text-xs bg-gray-100 text-gray-600 rounded;
  }

  .tool-description {
    @apply text-sm text-gray-600 mb-2;
  }

  .tool-params {
    @apply text-xs text-gray-500;
  }

  .execution-section {
    @apply border-t pt-6;
  }

  .tool-form {
    @apply space-y-4;
  }

  .arguments-form {
    @apply space-y-4;
  }

  .form-group {
    @apply space-y-1;
  }

  .form-label {
    @apply block text-sm font-medium text-gray-700;
  }

  .required {
    @apply text-red-500;
  }

  .form-help {
    @apply text-xs text-gray-500;
  }

  .form-input {
    @apply w-full px-3 py-2 border border-gray-300 rounded-lg text-sm;
  }

  .checkbox-label {
    @apply flex items-center space-x-2 cursor-pointer;
  }

  .form-actions {
    @apply flex space-x-3 pt-4;
  }

  .execution-result {
    @apply p-4 rounded-lg;
  }

  .execution-result.success {
    @apply bg-green-50 border border-green-200;
  }

  .execution-result.error {
    @apply bg-red-50 border border-red-200;
  }

  .result-title {
    @apply font-medium mb-2;
  }

  .result-content {
    @apply text-sm bg-white p-3 rounded border overflow-auto max-h-64;
  }

  .error-message {
    @apply text-red-600 text-sm;
  }

  .history-section {
    @apply border-t pt-6;
  }

  .history-list {
    @apply space-y-2;
  }

  .history-item {
    @apply p-3 rounded-lg border;
  }

  .history-item.success {
    @apply border-green-200 bg-green-50;
  }

  .history-item.error {
    @apply border-red-200 bg-red-50;
  }

  .history-header {
    @apply flex items-center space-x-2 text-sm;
  }

  .execution-duration {
    @apply text-xs text-gray-500 mt-1;
  }

  .execution-time {
    @apply text-xs text-gray-500 ml-auto;
  }

  .btn {
    @apply px-3 py-2 rounded text-sm font-medium transition-colors;
  }

  .btn-primary {
    @apply bg-blue-600 text-white hover:bg-blue-700 disabled:opacity-50;
  }

  .btn-outline {
    @apply border border-gray-300 text-gray-700 hover:bg-gray-50;
  }

  .btn-sm {
    @apply px-2 py-1 text-xs;
  }
</style>