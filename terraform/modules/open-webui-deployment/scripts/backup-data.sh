#!/bin/bash
set -euo pipefail

# Open WebUI Data Backup Script
# Backs up user data, uploads, and database to S3

# Configuration
CUSTOMER_NAME="${CUSTOMER_NAME:-default}"
S3_BUCKET_NAME="${S3_BUCKET_NAME:-}"
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/openwebui_backup_${BACKUP_TIMESTAMP}"
DATA_DIR="/app/backend/data"
UPLOADS_DIR="/app/backend/uploads"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    cleanup
    exit 1
}

# Cleanup function
cleanup() {
    log "Cleaning up temporary files..."
    rm -rf "$BACKUP_DIR" 2>/dev/null || true
}

# Check if required tools are available
check_dependencies() {
    log "Checking dependencies..."
    
    local deps=("aws" "tar" "gzip")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        error_exit "Missing dependencies: ${missing_deps[*]}"
    fi
    
    log "All dependencies available"
}

# Check S3 bucket configuration
check_s3_config() {
    log "Checking S3 configuration..."
    
    if [ -z "$S3_BUCKET_NAME" ]; then
        error_exit "S3_BUCKET_NAME environment variable not set"
    fi
    
    # Test S3 access
    if ! aws s3 ls "s3://$S3_BUCKET_NAME" > /dev/null 2>&1; then
        error_exit "Cannot access S3 bucket: $S3_BUCKET_NAME"
    fi
    
    log "S3 configuration verified"
}

# Create backup directory structure
create_backup_structure() {
    log "Creating backup directory structure..."
    
    mkdir -p "$BACKUP_DIR"/{data,uploads,database,metadata}
    
    log "Backup directory created: $BACKUP_DIR"
}

# Backup user data
backup_user_data() {
    log "Backing up user data..."
    
    if [ -d "$DATA_DIR" ]; then
        local data_size
        data_size=$(du -sh "$DATA_DIR" | cut -f1)
        log "Data directory size: $data_size"
        
        # Create compressed archive of data directory
        tar -czf "$BACKUP_DIR/data/user_data.tar.gz" -C "$(dirname "$DATA_DIR")" "$(basename "$DATA_DIR")" 2>/dev/null || {
            log "WARNING: Failed to backup user data directory"
            return 1
        }
        
        log "User data backup completed"
    else
        log "WARNING: Data directory not found: $DATA_DIR"
    fi
}

# Backup uploaded files
backup_uploads() {
    log "Backing up uploaded files..."
    
    if [ -d "$UPLOADS_DIR" ]; then
        local uploads_size
        uploads_size=$(du -sh "$UPLOADS_DIR" | cut -f1)
        log "Uploads directory size: $uploads_size"
        
        # Create compressed archive of uploads directory
        tar -czf "$BACKUP_DIR/uploads/uploads.tar.gz" -C "$(dirname "$UPLOADS_DIR")" "$(basename "$UPLOADS_DIR")" 2>/dev/null || {
            log "WARNING: Failed to backup uploads directory"
            return 1
        }
        
        log "Uploads backup completed"
    else
        log "WARNING: Uploads directory not found: $UPLOADS_DIR"
    fi
}

# Backup database
backup_database() {
    log "Backing up database..."
    
    local database_url="${DATABASE_URL:-}"
    
    if [ -z "$database_url" ]; then
        log "WARNING: DATABASE_URL not set, skipping database backup"
        return 0
    fi
    
    # Parse database URL to determine type
    local db_scheme
    db_scheme=$(echo "$database_url" | cut -d':' -f1)
    
    case "$db_scheme" in
        "sqlite")
            backup_sqlite_database "$database_url"
            ;;
        "postgresql"|"postgres")
            backup_postgresql_database "$database_url"
            ;;
        *)
            log "WARNING: Unsupported database type: $db_scheme"
            ;;
    esac
}

# Backup SQLite database
backup_sqlite_database() {
    local database_url="$1"
    local db_path
    db_path=$(echo "$database_url" | sed 's|sqlite:///||')
    
    if [ -f "$db_path" ]; then
        log "Backing up SQLite database: $db_path"
        
        # Copy SQLite database file
        cp "$db_path" "$BACKUP_DIR/database/database.sqlite" || {
            log "WARNING: Failed to backup SQLite database"
            return 1
        }
        
        # Compress the database file
        gzip "$BACKUP_DIR/database/database.sqlite"
        
        log "SQLite database backup completed"
    else
        log "WARNING: SQLite database file not found: $db_path"
    fi
}

# Backup PostgreSQL database
backup_postgresql_database() {
    local database_url="$1"
    
    log "Backing up PostgreSQL database..."
    
    # Extract connection parameters
    local db_host db_port db_name db_user db_password
    db_host=$(echo "$database_url" | sed -n 's|.*://[^:]*:\([^@]*\)@\([^:]*\):.*|\2|p')
    db_port=$(echo "$database_url" | sed -n 's|.*://[^:]*:[^@]*@[^:]*:\([0-9]*\)/.*|\1|p')
    db_name=$(echo "$database_url" | sed -n 's|.*/\([^?]*\).*|\1|p')
    db_user=$(echo "$database_url" | sed -n 's|.*://\([^:]*\):.*|\1|p')
    db_password=$(echo "$database_url" | sed -n 's|.*://[^:]*:\([^@]*\)@.*|\1|p')
    
    # Set PostgreSQL environment variables
    export PGPASSWORD="$db_password"
    
    # Create database dump
    if command -v pg_dump &> /dev/null; then
        pg_dump -h "$db_host" -p "${db_port:-5432}" -U "$db_user" -d "$db_name" \
                --no-password --verbose --format=custom \
                --file="$BACKUP_DIR/database/database.dump" || {
            log "WARNING: Failed to backup PostgreSQL database"
            return 1
        }
        
        # Compress the dump file
        gzip "$BACKUP_DIR/database/database.dump"
        
        log "PostgreSQL database backup completed"
    else
        log "WARNING: pg_dump not available, skipping PostgreSQL backup"
    fi
    
    unset PGPASSWORD
}

# Create backup metadata
create_backup_metadata() {
    log "Creating backup metadata..."
    
    local metadata_file="$BACKUP_DIR/metadata/backup_info.json"
    
    cat > "$metadata_file" << EOF
{
    "customer_name": "$CUSTOMER_NAME",
    "backup_timestamp": "$BACKUP_TIMESTAMP",
    "backup_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "hostname": "$(hostname)",
    "backup_type": "full",
    "components": {
        "user_data": $([ -f "$BACKUP_DIR/data/user_data.tar.gz" ] && echo "true" || echo "false"),
        "uploads": $([ -f "$BACKUP_DIR/uploads/uploads.tar.gz" ] && echo "true" || echo "false"),
        "database": $([ -f "$BACKUP_DIR/database/database.sqlite.gz" ] || [ -f "$BACKUP_DIR/database/database.dump.gz" ] && echo "true" || echo "false")
    },
    "sizes": {
        "user_data_bytes": $([ -f "$BACKUP_DIR/data/user_data.tar.gz" ] && stat -c%s "$BACKUP_DIR/data/user_data.tar.gz" || echo "0"),
        "uploads_bytes": $([ -f "$BACKUP_DIR/uploads/uploads.tar.gz" ] && stat -c%s "$BACKUP_DIR/uploads/uploads.tar.gz" || echo "0"),
        "database_bytes": $(find "$BACKUP_DIR/database" -name "*.gz" -exec stat -c%s {} \; 2>/dev/null | head -1 || echo "0")
    }
}
EOF
    
    log "Backup metadata created"
}

# Upload backup to S3
upload_to_s3() {
    log "Uploading backup to S3..."
    
    local s3_prefix="openwebui-backups/$CUSTOMER_NAME/$BACKUP_TIMESTAMP"
    
    # Upload backup directory to S3
    if aws s3 cp "$BACKUP_DIR" "s3://$S3_BUCKET_NAME/$s3_prefix/" --recursive --storage-class STANDARD_IA; then
        log "Backup uploaded to s3://$S3_BUCKET_NAME/$s3_prefix/"
        
        # Create a latest backup symlink
        local latest_prefix="openwebui-backups/$CUSTOMER_NAME/latest"
        aws s3 cp "s3://$S3_BUCKET_NAME/$s3_prefix/metadata/backup_info.json" \
                  "s3://$S3_BUCKET_NAME/$latest_prefix/backup_info.json" || true
        
        return 0
    else
        error_exit "Failed to upload backup to S3"
    fi
}

# Clean up old backups
cleanup_old_backups() {
    log "Cleaning up backups older than $RETENTION_DAYS days..."
    
    local cutoff_date
    cutoff_date=$(date -d "$RETENTION_DAYS days ago" +%Y-%m-%d)
    
    # List and delete old backups
    aws s3api list-objects-v2 \
        --bucket "$S3_BUCKET_NAME" \
        --prefix "openwebui-backups/$CUSTOMER_NAME/" \
        --query "Contents[?LastModified<='$cutoff_date'].Key" \
        --output text | \
    while read -r key; do
        if [ -n "$key" ] && [ "$key" != "None" ]; then
            log "Deleting old backup: $key"
            aws s3 rm "s3://$S3_BUCKET_NAME/$key" || true
        fi
    done
    
    log "Old backup cleanup completed"
}

# Calculate backup statistics
calculate_stats() {
    log "Calculating backup statistics..."
    
    local total_size=0
    local file_count=0
    
    while IFS= read -r -d '' file; do
        local size
        size=$(stat -c%s "$file" 2>/dev/null || echo "0")
        total_size=$((total_size + size))
        file_count=$((file_count + 1))
    done < <(find "$BACKUP_DIR" -type f -print0)
    
    local total_size_mb=$((total_size / 1024 / 1024))
    
    log "Backup statistics:"
    log "  Total files: $file_count"
    log "  Total size: ${total_size_mb}MB"
    log "  Backup location: s3://$S3_BUCKET_NAME/openwebui-backups/$CUSTOMER_NAME/$BACKUP_TIMESTAMP/"
}

# Main backup function
main() {
    log "Starting Open WebUI backup for customer: $CUSTOMER_NAME"
    
    # Set trap for cleanup on exit
    trap cleanup EXIT
    
    # Check dependencies and configuration
    check_dependencies
    check_s3_config
    
    # Create backup structure
    create_backup_structure
    
    # Perform backups
    backup_user_data
    backup_uploads
    backup_database
    
    # Create metadata
    create_backup_metadata
    
    # Calculate statistics
    calculate_stats
    
    # Upload to S3
    upload_to_s3
    
    # Clean up old backups
    cleanup_old_backups
    
    log "Backup completed successfully!"
}

# Run main function
main "$@"