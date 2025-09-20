#!/bin/bash
set -euo pipefail

# Ollama Model Cleanup Script
# Removes unused models and cleans up storage space

# Configuration
OLLAMA_HOST="${OLLAMA_HOST:-localhost:11434}"
CLEANUP_THRESHOLD_GB="${CLEANUP_THRESHOLD_GB:-10}"
MAX_MODEL_AGE_DAYS="${MAX_MODEL_AGE_DAYS:-30}"
DRY_RUN="${DRY_RUN:-false}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Check available disk space
check_disk_space() {
    local available_gb
    available_gb=$(df /models | tail -1 | awk '{print int($4/1024/1024)}')
    
    log "Available disk space: ${available_gb}GB"
    echo "$available_gb"
}

# Get list of all models
get_all_models() {
    log "Getting list of all models..."
    
    local response
    if response=$(curl -s -f "http://$OLLAMA_HOST/api/tags" 2>/dev/null); then
        echo "$response" | jq -r '.models[].name' 2>/dev/null || echo ""
    else
        error_exit "Failed to get model list from Ollama API"
    fi
}

# Get list of loaded models
get_loaded_models() {
    log "Getting list of loaded models..."
    
    local response
    if response=$(curl -s -f "http://$OLLAMA_HOST/api/ps" 2>/dev/null); then
        echo "$response" | jq -r '.models[].name' 2>/dev/null || echo ""
    else
        log "WARNING: Failed to get loaded models list"
        echo ""
    fi
}

# Get model size
get_model_size() {
    local model_name=$1
    
    local response
    if response=$(curl -s -f -X POST -H "Content-Type: application/json" \
                      -d "{\"name\":\"$model_name\"}" \
                      "http://$OLLAMA_HOST/api/show" 2>/dev/null); then
        
        local size_bytes
        size_bytes=$(echo "$response" | jq -r '.details.parameter_size // 0' 2>/dev/null || echo "0")
        
        # Convert to GB
        echo "scale=2; $size_bytes / 1024 / 1024 / 1024" | bc -l 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Get model last modified time (from filesystem)
get_model_last_modified() {
    local model_name=$1
    local model_dir="/models/blobs"
    
    if [ -d "$model_dir" ]; then
        # Find the most recent file related to this model
        local last_modified
        last_modified=$(find "$model_dir" -name "*" -type f -printf '%T@ %p\n' 2>/dev/null | \
                       sort -n | tail -1 | cut -d' ' -f1 || echo "0")
        
        if [ "$last_modified" != "0" ]; then
            # Convert to days ago
            local current_time
            current_time=$(date +%s)
            local days_ago
            days_ago=$(echo "scale=0; ($current_time - $last_modified) / 86400" | bc -l 2>/dev/null || echo "999")
            echo "$days_ago"
        else
            echo "999"
        fi
    else
        echo "999"
    fi
}

# Remove a model
remove_model() {
    local model_name=$1
    
    log "Removing model: $model_name"
    
    if [ "$DRY_RUN" = "true" ]; then
        log "DRY RUN: Would remove model $model_name"
        return 0
    fi
    
    local response
    if response=$(curl -s -X DELETE "http://$OLLAMA_HOST/api/delete" \
                      -H "Content-Type: application/json" \
                      -d "{\"name\":\"$model_name\"}" 2>/dev/null); then
        
        if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
            local error_msg
            error_msg=$(echo "$response" | jq -r '.error')
            log "ERROR: Failed to remove model $model_name: $error_msg"
            return 1
        else
            log "Successfully removed model: $model_name"
            return 0
        fi
    else
        log "ERROR: Failed to remove model $model_name (API call failed)"
        return 1
    fi
}

# Clean up unused models based on age
cleanup_old_models() {
    log "Cleaning up models older than $MAX_MODEL_AGE_DAYS days..."
    
    local all_models
    all_models=$(get_all_models)
    
    local loaded_models
    loaded_models=$(get_loaded_models)
    
    local removed_count=0
    local total_size_freed=0
    
    while IFS= read -r model; do
        if [ -n "$model" ]; then
            # Skip if model is currently loaded
            if echo "$loaded_models" | grep -q "^$model$"; then
                log "Skipping loaded model: $model"
                continue
            fi
            
            local days_old
            days_old=$(get_model_last_modified "$model")
            
            if [ "$days_old" -gt "$MAX_MODEL_AGE_DAYS" ]; then
                local model_size
                model_size=$(get_model_size "$model")
                
                log "Model $model is $days_old days old (${model_size}GB) - marking for removal"
                
                if remove_model "$model"; then
                    ((removed_count++))
                    total_size_freed=$(echo "$total_size_freed + $model_size" | bc -l)
                fi
            else
                log "Model $model is $days_old days old - keeping"
            fi
        fi
    done <<< "$all_models"
    
    log "Cleanup summary: Removed $removed_count models, freed ${total_size_freed}GB"
}

# Clean up models to free space
cleanup_for_space() {
    local target_free_gb=$1
    
    log "Cleaning up models to free at least ${target_free_gb}GB..."
    
    local all_models
    all_models=$(get_all_models)
    
    local loaded_models
    loaded_models=$(get_loaded_models)
    
    # Create array of models with their info
    declare -a model_info
    
    while IFS= read -r model; do
        if [ -n "$model" ]; then
            # Skip if model is currently loaded
            if echo "$loaded_models" | grep -q "^$model$"; then
                continue
            fi
            
            local days_old
            days_old=$(get_model_last_modified "$model")
            
            local model_size
            model_size=$(get_model_size "$model")
            
            # Store model info: "days_old:size:name"
            model_info+=("$days_old:$model_size:$model")
        fi
    done <<< "$all_models"
    
    # Sort by age (oldest first)
    IFS=$'\n' sorted_models=($(sort -n <<< "${model_info[*]}"))
    unset IFS
    
    local freed_space=0
    local removed_count=0
    
    for model_entry in "${sorted_models[@]}"; do
        if [ -z "$model_entry" ]; then
            continue
        fi
        
        local days_old
        local model_size
        local model_name
        
        IFS=':' read -r days_old model_size model_name <<< "$model_entry"
        
        log "Considering model $model_name (${days_old} days old, ${model_size}GB)"
        
        if remove_model "$model_name"; then
            freed_space=$(echo "$freed_space + $model_size" | bc -l)
            ((removed_count++))
            
            log "Freed ${model_size}GB (total: ${freed_space}GB)"
            
            # Check if we've freed enough space
            if [ "$(echo "$freed_space >= $target_free_gb" | bc -l)" -eq 1 ]; then
                log "Target space freed: ${freed_space}GB"
                break
            fi
        fi
    done
    
    log "Space cleanup summary: Removed $removed_count models, freed ${freed_space}GB"
}

# Clean up temporary files and caches
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    local temp_dirs=("/tmp/ollama*" "/models/.tmp*" "/models/tmp*")
    local cleaned_size=0
    
    for pattern in "${temp_dirs[@]}"; do
        if [ "$DRY_RUN" = "true" ]; then
            local size
            size=$(du -sb $pattern 2>/dev/null | awk '{sum+=$1} END {print sum/1024/1024/1024}' || echo "0")
            log "DRY RUN: Would clean temporary files matching $pattern (${size}GB)"
            cleaned_size=$(echo "$cleaned_size + $size" | bc -l)
        else
            local size
            size=$(du -sb $pattern 2>/dev/null | awk '{sum+=$1} END {print sum/1024/1024/1024}' || echo "0")
            
            if [ "$(echo "$size > 0" | bc -l)" -eq 1 ]; then
                rm -rf $pattern 2>/dev/null || true
                log "Cleaned temporary files: ${size}GB"
                cleaned_size=$(echo "$cleaned_size + $size" | bc -l)
            fi
        fi
    done
    
    log "Temporary file cleanup freed: ${cleaned_size}GB"
}

# Main cleanup function
main() {
    log "Starting Ollama model cleanup..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log "Running in DRY RUN mode - no changes will be made"
    fi
    
    # Check current disk space
    local available_gb
    available_gb=$(check_disk_space)
    
    # Clean up temporary files first
    cleanup_temp_files
    
    # Check if we need to free space
    if [ "$available_gb" -lt "$CLEANUP_THRESHOLD_GB" ]; then
        log "Available space (${available_gb}GB) is below threshold (${CLEANUP_THRESHOLD_GB}GB)"
        
        local space_needed
        space_needed=$(echo "$CLEANUP_THRESHOLD_GB - $available_gb + 5" | bc -l)  # Add 5GB buffer
        
        cleanup_for_space "$space_needed"
    else
        log "Available space (${available_gb}GB) is above threshold (${CLEANUP_THRESHOLD_GB}GB)"
    fi
    
    # Always clean up old models
    cleanup_old_models
    
    # Final disk space check
    local final_available
    final_available=$(check_disk_space)
    
    local space_freed
    space_freed=$(echo "$final_available - $available_gb" | bc -l)
    
    log "Cleanup completed. Space freed: ${space_freed}GB"
    log "Final available space: ${final_available}GB"
}

# Check dependencies
if ! command -v jq &> /dev/null; then
    error_exit "jq is required but not installed"
fi

if ! command -v bc &> /dev/null; then
    error_exit "bc is required but not installed"
fi

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --threshold)
            CLEANUP_THRESHOLD_GB="$2"
            shift 2
            ;;
        --max-age)
            MAX_MODEL_AGE_DAYS="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run           Run without making changes"
            echo "  --threshold GB      Disk space threshold for cleanup (default: 10)"
            echo "  --max-age DAYS      Maximum age for models in days (default: 30)"
            echo "  -h, --help          Show this help message"
            exit 0
            ;;
        *)
            error_exit "Unknown option: $1"
            ;;
    esac
done

# Run main function
main "$@"