#!/bin/bash
set -euo pipefail

# Ollama Model Download Script
# Downloads and prepares models during container initialization

# Configuration
MODELS_CONFIG="/config/models.json"
OLLAMA_HOST="${OLLAMA_HOST:-localhost:11434}"
DOWNLOAD_TIMEOUT="${DOWNLOAD_TIMEOUT:-3600}"
MAX_RETRIES=3

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Wait for Ollama server to be ready
wait_for_ollama() {
    log "Waiting for Ollama server to be ready..."
    
    local max_attempts=60
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -f "http://$OLLAMA_HOST/api/tags" > /dev/null 2>&1; then
            log "Ollama server is ready"
            return 0
        fi
        
        log "Attempt $attempt/$max_attempts: Ollama not ready, waiting..."
        sleep 5
        ((attempt++))
    done
    
    error_exit "Ollama server did not become ready within timeout"
}

# Start Ollama server in background for model downloads
start_ollama_server() {
    log "Starting Ollama server for model downloads..."
    
    # Start Ollama in background
    ollama serve &
    OLLAMA_PID=$!
    
    # Wait for server to be ready
    wait_for_ollama
    
    log "Ollama server started with PID: $OLLAMA_PID"
}

# Stop Ollama server
stop_ollama_server() {
    if [ -n "${OLLAMA_PID:-}" ]; then
        log "Stopping Ollama server (PID: $OLLAMA_PID)..."
        kill $OLLAMA_PID 2>/dev/null || true
        wait $OLLAMA_PID 2>/dev/null || true
    fi
}

# Download a single model with retries
download_model() {
    local model_name=$1
    local attempt=1
    
    log "Downloading model: $model_name"
    
    while [ $attempt -le $MAX_RETRIES ]; do
        log "Attempt $attempt/$MAX_RETRIES for model: $model_name"
        
        if timeout $DOWNLOAD_TIMEOUT ollama pull "$model_name"; then
            log "Successfully downloaded model: $model_name"
            return 0
        else
            log "Failed to download model: $model_name (attempt $attempt)"
            ((attempt++))
            
            if [ $attempt -le $MAX_RETRIES ]; then
                log "Retrying in 30 seconds..."
                sleep 30
            fi
        fi
    done
    
    log "ERROR: Failed to download model after $MAX_RETRIES attempts: $model_name"
    return 1
}

# Create model configuration
create_model_config() {
    local model_name=$1
    local config_data=$2
    
    if [ "$config_data" != "null" ] && [ -n "$config_data" ]; then
        log "Creating configuration for model: $model_name"
        
        local modelfile="/tmp/${model_name//[:\/]/_}.Modelfile"
        
        # Extract configuration parameters
        local parameters=$(echo "$config_data" | jq -r '.parameters // {}' | jq -r 'to_entries[] | "PARAMETER \(.key) \(.value)"')
        local template=$(echo "$config_data" | jq -r '.template // ""')
        local system=$(echo "$config_data" | jq -r '.system // ""')
        
        # Create Modelfile
        cat > "$modelfile" << EOF
FROM $model_name

# Parameters
$parameters

# Template
$([ -n "$template" ] && echo "TEMPLATE \"$template\"")

# System message
$([ -n "$system" ] && echo "SYSTEM \"$system\"")
EOF
        
        # Create the configured model
        local configured_name="${model_name}-configured"
        if ollama create "$configured_name" -f "$modelfile"; then
            log "Created configured model: $configured_name"
        else
            log "WARNING: Failed to create configured model: $configured_name"
        fi
        
        rm -f "$modelfile"
    fi
}

# Get model list from configuration
get_model_list() {
    if [ -f "$MODELS_CONFIG" ]; then
        jq -r '.default_models[]' "$MODELS_CONFIG" 2>/dev/null || echo ""
    else
        log "WARNING: Models configuration file not found: $MODELS_CONFIG"
        echo ""
    fi
}

# Get model configuration
get_model_config() {
    local model_name=$1
    
    if [ -f "$MODELS_CONFIG" ]; then
        jq -r ".model_configs[\"$model_name\"] // null" "$MODELS_CONFIG" 2>/dev/null || echo "null"
    else
        echo "null"
    fi
}

# Check available disk space
check_disk_space() {
    local available_gb
    available_gb=$(df /models | tail -1 | awk '{print int($4/1024/1024)}')
    
    log "Available disk space: ${available_gb}GB"
    
    if [ "$available_gb" -lt 10 ]; then
        error_exit "Insufficient disk space for model downloads (less than 10GB available)"
    fi
}

# List existing models
list_existing_models() {
    log "Checking for existing models..."
    
    if [ -d "/models" ] && [ "$(ls -A /models 2>/dev/null)" ]; then
        log "Found existing models in /models:"
        ls -la /models/ || true
    else
        log "No existing models found"
    fi
}

# Cleanup function
cleanup() {
    log "Cleaning up..."
    stop_ollama_server
    
    # Clean up temporary files
    rm -f /tmp/*.Modelfile 2>/dev/null || true
}

# Main function
main() {
    log "Starting Ollama model download process..."
    
    # Set trap for cleanup
    trap cleanup EXIT
    
    # Check disk space
    check_disk_space
    
    # List existing models
    list_existing_models
    
    # Start Ollama server
    start_ollama_server
    
    # Get list of models to download
    local models
    models=$(get_model_list)
    
    if [ -z "$models" ]; then
        log "No models configured for download"
        return 0
    fi
    
    log "Models to download: $(echo "$models" | tr '\n' ' ')"
    
    # Download each model
    local failed_models=()
    while IFS= read -r model; do
        if [ -n "$model" ]; then
            if download_model "$model"; then
                # Create model configuration if specified
                local config_data
                config_data=$(get_model_config "$model")
                create_model_config "$model" "$config_data"
            else
                failed_models+=("$model")
            fi
        fi
    done <<< "$models"
    
    # Report results
    if [ ${#failed_models[@]} -eq 0 ]; then
        log "All models downloaded successfully!"
    else
        log "WARNING: Failed to download the following models: ${failed_models[*]}"
        log "Container will continue to start, but these models will not be available"
    fi
    
    # List final models
    log "Final model list:"
    ollama list || true
    
    log "Model download process completed"
}

# Check if jq is available
if ! command -v jq &> /dev/null; then
    log "Installing jq..."
    apt-get update && apt-get install -y jq
fi

# Run main function
main "$@"