#!/bin/bash
set -euo pipefail

# Qdrant Backup Script
# This script creates snapshots of Qdrant collections and uploads them to S3

# Configuration
CUSTOMER_NAME="${customer_name}"
BACKUP_S3_BUCKET="${backup_s3_bucket}"
BACKUP_RETENTION_DAYS="${backup_retention_days}"
QDRANT_SERVICE="${qdrant_service_name}.${qdrant_namespace}.svc.cluster.local:6333"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/qdrant_backup_$${TIMESTAMP}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Check if required tools are available
check_dependencies() {
    log "Checking dependencies..."
    
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI not found"
    fi
    
    if ! command -v curl &> /dev/null; then
        error_exit "curl not found"
    fi
    
    if ! command -v jq &> /dev/null; then
        # Install jq if not available
        log "Installing jq..."
        apt-get update && apt-get install -y jq
    fi
}

# Wait for Qdrant to be ready
wait_for_qdrant() {
    log "Waiting for Qdrant to be ready..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -f "http://$${QDRANT_SERVICE}/health" > /dev/null; then
            log "Qdrant is ready"
            return 0
        fi
        
        log "Attempt $${attempt}/$${max_attempts}: Qdrant not ready, waiting..."
        sleep 10
        ((attempt++))
    done
    
    error_exit "Qdrant did not become ready within timeout"
}

# Get list of collections
get_collections() {
    log "Getting list of collections..."
    
    local auth_header=""
    if [ -n "${QDRANT_API_KEY:-}" ]; then
        auth_header="-H 'api-key: $${QDRANT_API_KEY}'"
    fi
    
    local collections
    collections=$(eval curl -s $${auth_header} "http://$${QDRANT_SERVICE}/collections" | jq -r '.result.collections[].name')
    
    if [ -z "$collections" ]; then
        log "No collections found"
        return 1
    fi
    
    echo "$collections"
}

# Create snapshot for a collection
create_snapshot() {
    local collection_name=$1
    log "Creating snapshot for collection: $${collection_name}"
    
    local auth_header=""
    if [ -n "${QDRANT_API_KEY:-}" ]; then
        auth_header="-H 'api-key: $${QDRANT_API_KEY}'"
    fi
    
    local snapshot_response
    snapshot_response=$(eval curl -s -X POST $${auth_header} "http://$${QDRANT_SERVICE}/collections/$${collection_name}/snapshots")
    
    local snapshot_name
    snapshot_name=$(echo "$snapshot_response" | jq -r '.result.name')
    
    if [ "$snapshot_name" = "null" ] || [ -z "$snapshot_name" ]; then
        error_exit "Failed to create snapshot for collection $${collection_name}"
    fi
    
    log "Created snapshot: $${snapshot_name}"
    echo "$snapshot_name"
}

# Download snapshot
download_snapshot() {
    local collection_name=$1
    local snapshot_name=$2
    
    log "Downloading snapshot $${snapshot_name} for collection $${collection_name}..."
    
    local auth_header=""
    if [ -n "${QDRANT_API_KEY:-}" ]; then
        auth_header="-H 'api-key: $${QDRANT_API_KEY}'"
    fi
    
    mkdir -p "$${BACKUP_DIR}/$${collection_name}"
    
    local output_file="$${BACKUP_DIR}/$${collection_name}/$${snapshot_name}"
    
    if ! eval curl -s $${auth_header} "http://$${QDRANT_SERVICE}/collections/$${collection_name}/snapshots/$${snapshot_name}" -o "$${output_file}"; then
        error_exit "Failed to download snapshot $${snapshot_name}"
    fi
    
    log "Downloaded snapshot to $${output_file}"
}

# Upload backup to S3
upload_to_s3() {
    log "Uploading backup to S3..."
    
    local s3_prefix="qdrant-backups/$${CUSTOMER_NAME}/$${TIMESTAMP}"
    
    if ! aws s3 cp "$${BACKUP_DIR}" "s3://$${BACKUP_S3_BUCKET}/$${s3_prefix}/" --recursive; then
        error_exit "Failed to upload backup to S3"
    fi
    
    log "Backup uploaded to s3://$${BACKUP_S3_BUCKET}/$${s3_prefix}/"
}

# Clean up old backups
cleanup_old_backups() {
    log "Cleaning up backups older than $${BACKUP_RETENTION_DAYS} days..."
    
    local cutoff_date
    cutoff_date=$(date -d "$${BACKUP_RETENTION_DAYS} days ago" +%Y-%m-%d)
    
    # List and delete old backups
    aws s3api list-objects-v2 \
        --bucket "$${BACKUP_S3_BUCKET}" \
        --prefix "qdrant-backups/$${CUSTOMER_NAME}/" \
        --query "Contents[?LastModified<='$${cutoff_date}'].Key" \
        --output text | \
    while read -r key; do
        if [ -n "$key" ] && [ "$key" != "None" ]; then
            log "Deleting old backup: $key"
            aws s3 rm "s3://$${BACKUP_S3_BUCKET}/$key"
        fi
    done
}

# Create backup manifest
create_manifest() {
    log "Creating backup manifest..."
    
    local manifest_file="$${BACKUP_DIR}/manifest.json"
    
    cat > "$${manifest_file}" << EOF
{
    "customer_name": "$${CUSTOMER_NAME}",
    "timestamp": "$${TIMESTAMP}",
    "backup_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "qdrant_version": "$(curl -s http://$${QDRANT_SERVICE}/ | jq -r '.version // "unknown"')",
    "collections": [
$(find "$${BACKUP_DIR}" -name "*.snapshot" -type f | while read -r file; do
    collection=$(basename $(dirname "$file"))
    snapshot=$(basename "$file")
    size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file")
    echo "        {\"collection\": \"$collection\", \"snapshot\": \"$snapshot\", \"size_bytes\": $size}"
done | paste -sd ',' -)
    ]
}
EOF
    
    log "Manifest created at $${manifest_file}"
}

# Cleanup temporary files
cleanup() {
    log "Cleaning up temporary files..."
    rm -rf "$${BACKUP_DIR}"
}

# Main backup function
main() {
    log "Starting Qdrant backup for customer: $${CUSTOMER_NAME}"
    
    # Check dependencies
    check_dependencies
    
    # Wait for Qdrant
    wait_for_qdrant
    
    # Create backup directory
    mkdir -p "$${BACKUP_DIR}"
    
    # Get collections and create snapshots
    local collections
    collections=$(get_collections)
    
    if [ -z "$collections" ]; then
        log "No collections to backup"
        cleanup
        exit 0
    fi
    
    # Process each collection
    while IFS= read -r collection; do
        if [ -n "$collection" ]; then
            local snapshot_name
            snapshot_name=$(create_snapshot "$collection")
            
            # Wait a moment for snapshot to be ready
            sleep 5
            
            download_snapshot "$collection" "$snapshot_name"
        fi
    done <<< "$collections"
    
    # Create manifest
    create_manifest
    
    # Upload to S3
    upload_to_s3
    
    # Clean up old backups
    cleanup_old_backups
    
    # Clean up temporary files
    cleanup
    
    log "Backup completed successfully"
}

# Set trap for cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"