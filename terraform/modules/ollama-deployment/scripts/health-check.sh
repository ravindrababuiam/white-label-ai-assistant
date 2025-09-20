#!/bin/bash
set -euo pipefail

# Ollama Health Check Script
# Performs comprehensive health checks for Ollama service

# Configuration
OLLAMA_HOST="${OLLAMA_HOST:-localhost:11434}"
TIMEOUT=10
VERBOSE=${VERBOSE:-false}

# Logging function
log() {
    if [ "$VERBOSE" = "true" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    fi
}

# Error function
error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

# Check if Ollama API is responding
check_api_health() {
    log "Checking Ollama API health..."
    
    local response
    if response=$(curl -s -f --max-time $TIMEOUT "http://$OLLAMA_HOST/api/tags" 2>/dev/null); then
        log "API health check passed"
        return 0
    else
        error "API health check failed - server not responding"
        return 1
    fi
}

# Check if models are loaded
check_models() {
    log "Checking available models..."
    
    local response
    if response=$(curl -s -f --max-time $TIMEOUT "http://$OLLAMA_HOST/api/tags" 2>/dev/null); then
        local model_count
        model_count=$(echo "$response" | jq -r '.models | length' 2>/dev/null || echo "0")
        
        if [ "$model_count" -gt 0 ]; then
            log "Found $model_count models available"
            if [ "$VERBOSE" = "true" ]; then
                echo "$response" | jq -r '.models[].name' 2>/dev/null || true
            fi
            return 0
        else
            error "No models available"
            return 1
        fi
    else
        error "Failed to retrieve model list"
        return 1
    fi
}

# Test model inference (if models are available)
test_inference() {
    log "Testing model inference..."
    
    # Get first available model
    local model_name
    model_name=$(curl -s -f --max-time $TIMEOUT "http://$OLLAMA_HOST/api/tags" 2>/dev/null | \
                jq -r '.models[0].name' 2>/dev/null || echo "")
    
    if [ -z "$model_name" ] || [ "$model_name" = "null" ]; then
        log "No models available for inference test"
        return 0  # Not a failure if no models are loaded
    fi
    
    log "Testing inference with model: $model_name"
    
    # Simple test prompt
    local test_payload
    test_payload=$(cat << EOF
{
    "model": "$model_name",
    "prompt": "Hello",
    "stream": false,
    "options": {
        "num_predict": 5
    }
}
EOF
)
    
    local response
    if response=$(curl -s -f --max-time 30 \
                      -H "Content-Type: application/json" \
                      -d "$test_payload" \
                      "http://$OLLAMA_HOST/api/generate" 2>/dev/null); then
        
        local response_text
        response_text=$(echo "$response" | jq -r '.response' 2>/dev/null || echo "")
        
        if [ -n "$response_text" ] && [ "$response_text" != "null" ]; then
            log "Inference test passed - received response"
            return 0
        else
            error "Inference test failed - no response generated"
            return 1
        fi
    else
        error "Inference test failed - API call failed"
        return 1
    fi
}

# Check disk space
check_disk_space() {
    log "Checking disk space..."
    
    local available_gb
    available_gb=$(df /models 2>/dev/null | tail -1 | awk '{print int($4/1024/1024)}' || echo "0")
    
    if [ "$available_gb" -lt 1 ]; then
        error "Critical: Less than 1GB disk space available"
        return 1
    elif [ "$available_gb" -lt 5 ]; then
        error "Warning: Less than 5GB disk space available"
        return 1
    else
        log "Disk space OK: ${available_gb}GB available"
        return 0
    fi
}

# Check memory usage
check_memory() {
    log "Checking memory usage..."
    
    local memory_info
    if memory_info=$(cat /proc/meminfo 2>/dev/null); then
        local total_mem
        local available_mem
        local used_percent
        
        total_mem=$(echo "$memory_info" | grep MemTotal | awk '{print $2}')
        available_mem=$(echo "$memory_info" | grep MemAvailable | awk '{print $2}')
        
        if [ -n "$total_mem" ] && [ -n "$available_mem" ] && [ "$total_mem" -gt 0 ]; then
            used_percent=$(( (total_mem - available_mem) * 100 / total_mem ))
            
            log "Memory usage: ${used_percent}%"
            
            if [ "$used_percent" -gt 95 ]; then
                error "Critical: Memory usage above 95%"
                return 1
            elif [ "$used_percent" -gt 90 ]; then
                error "Warning: Memory usage above 90%"
                return 1
            else
                return 0
            fi
        else
            log "Unable to determine memory usage"
            return 0
        fi
    else
        log "Unable to read memory information"
        return 0
    fi
}

# Check GPU status (if GPU is enabled)
check_gpu() {
    if [ "${NVIDIA_VISIBLE_DEVICES:-}" = "all" ] || [ -n "${NVIDIA_VISIBLE_DEVICES:-}" ]; then
        log "Checking GPU status..."
        
        if command -v nvidia-smi &> /dev/null; then
            if nvidia-smi -q -d MEMORY 2>/dev/null | grep -q "GPU"; then
                log "GPU check passed"
                return 0
            else
                error "GPU check failed - no GPUs detected"
                return 1
            fi
        else
            log "nvidia-smi not available, skipping GPU check"
            return 0
        fi
    else
        log "GPU not enabled, skipping GPU check"
        return 0
    fi
}

# Main health check function
main() {
    local exit_code=0
    local checks_passed=0
    local checks_total=0
    
    log "Starting Ollama health check..."
    
    # API Health Check
    ((checks_total++))
    if check_api_health; then
        ((checks_passed++))
    else
        exit_code=1
    fi
    
    # Model Check
    ((checks_total++))
    if check_models; then
        ((checks_passed++))
    else
        exit_code=1
    fi
    
    # Inference Test (optional)
    if [ "${SKIP_INFERENCE_TEST:-false}" != "true" ]; then
        ((checks_total++))
        if test_inference; then
            ((checks_passed++))
        else
            exit_code=1
        fi
    fi
    
    # Disk Space Check
    ((checks_total++))
    if check_disk_space; then
        ((checks_passed++))
    else
        exit_code=1
    fi
    
    # Memory Check
    ((checks_total++))
    if check_memory; then
        ((checks_passed++))
    else
        exit_code=1
    fi
    
    # GPU Check
    ((checks_total++))
    if check_gpu; then
        ((checks_passed++))
    else
        exit_code=1
    fi
    
    # Summary
    if [ "$exit_code" -eq 0 ]; then
        log "Health check passed: $checks_passed/$checks_total checks successful"
    else
        error "Health check failed: $checks_passed/$checks_total checks successful"
    fi
    
    exit $exit_code
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --skip-inference)
            SKIP_INFERENCE_TEST=true
            shift
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  -v, --verbose       Enable verbose output"
            echo "  --skip-inference    Skip inference test"
            echo "  --timeout SECONDS   Set timeout for API calls (default: 10)"
            echo "  -h, --help          Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if jq is available
if ! command -v jq &> /dev/null; then
    error "jq is required but not installed"
    exit 1
fi

# Run main function
main "$@"