#!/bin/bash

# LiteLLM-Lago Integration Service Deployment Script
set -e

# Configuration
COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env"
BACKUP_DIR="./backups"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Docker is installed and running
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker is not running. Please start Docker first."
        exit 1
    fi
    
    # Check if Docker Compose is available
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not available. Please install Docker Compose."
        exit 1
    fi
    
    # Check if .env file exists
    if [ ! -f "$ENV_FILE" ]; then
        log_warn ".env file not found. Creating from .env.example..."
        if [ -f ".env.example" ]; then
            cp .env.example .env
            log_warn "Please edit .env file with your configuration before continuing."
            exit 1
        else
            log_error ".env.example file not found. Cannot create .env file."
            exit 1
        fi
    fi
    
    # Validate required environment variables
    source .env
    required_vars=("POSTGRES_PASSWORD" "LITELLM_MASTER_KEY" "LAGO_API_KEY")
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            log_error "Required environment variable $var is not set in .env file"
            exit 1
        fi
    done
    
    log_info "Prerequisites check completed."
}

create_backup() {
    if [ "$1" = "true" ]; then
        log_info "Creating backup..."
        mkdir -p "$BACKUP_DIR"
        
        # Backup database if running
        if docker-compose ps postgres | grep -q "Up"; then
            BACKUP_FILE="$BACKUP_DIR/integration_backup_$(date +%Y%m%d_%H%M%S).sql"
            docker-compose exec -T postgres pg_dump -U integration integration > "$BACKUP_FILE"
            log_info "Database backup created: $BACKUP_FILE"
        fi
        
        # Backup configuration
        CONFIG_BACKUP="$BACKUP_DIR/config_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
        tar -czf "$CONFIG_BACKUP" .env docker-compose.yml config/
        log_info "Configuration backup created: $CONFIG_BACKUP"
    fi
}

wait_for_service() {
    local service_name=$1
    local health_check=$2
    local max_attempts=30
    local attempt=1
    
    log_info "Waiting for $service_name to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        if eval "$health_check" &> /dev/null; then
            log_info "$service_name is ready!"
            return 0
        fi
        
        log_debug "Attempt $attempt/$max_attempts: $service_name not ready yet..."
        sleep 10
        ((attempt++))
    done
    
    log_error "$service_name failed to become ready after $max_attempts attempts"
    return 1
}

deploy_services() {
    log_info "Deploying integration services..."
    
    # Build the application image
    log_info "Building application image..."
    docker-compose build
    
    # Start database and Redis first
    log_info "Starting database and Redis..."
    docker-compose up -d postgres redis
    
    # Wait for database to be ready
    wait_for_service "PostgreSQL" "docker-compose exec postgres pg_isready -U integration -d integration"
    wait_for_service "Redis" "docker-compose exec redis redis-cli ping | grep -q PONG"
    
    # Start all services
    log_info "Starting all services..."
    docker-compose up -d
    
    # Wait for services to be healthy
    log_info "Waiting for services to be healthy..."
    wait_for_service "Integration Service" "curl -f http://localhost:8080/health"
    
    log_info "All services are running!")
}

setup_customer_mappings() {
    log_info "Setting up customer mappings..."
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        log_warn "curl not found. Skipping automatic customer mapping setup."
        return
    fi
    
    # Wait a bit for service to be fully ready
    sleep 10
    
    # Create sample customer mappings
    log_info "Creating sample customer mappings..."
    
    # Customer 1
    curl -X POST http://localhost:8080/customers/mapping \
        -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
        -H "Content-Type: application/json" \
        -d '{
            "litellm_customer_id": "demo-customer-1",
            "lago_customer_id": "lago-customer-1",
            "lago_organization_id": "lago-org-1",
            "billing_plan": "ai_basic",
            "is_active": true
        }' &> /dev/null && log_info "Created mapping for demo-customer-1" || log_warn "Failed to create mapping for demo-customer-1"
    
    # Customer 2
    curl -X POST http://localhost:8080/customers/mapping \
        -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
        -H "Content-Type: application/json" \
        -d '{
            "litellm_customer_id": "demo-customer-2",
            "lago_customer_id": "lago-customer-2", 
            "lago_organization_id": "lago-org-1",
            "billing_plan": "ai_premium",
            "is_active": true
        }' &> /dev/null && log_info "Created mapping for demo-customer-2" || log_warn "Failed to create mapping for demo-customer-2"
}

check_service_health() {
    log_info "Checking service health..."
    
    local all_healthy=true
    
    # Check PostgreSQL
    if docker-compose exec postgres pg_isready -U integration -d integration &> /dev/null; then
        log_info "✓ PostgreSQL is healthy"
    else
        log_error "✗ PostgreSQL is not healthy"
        all_healthy=false
    fi
    
    # Check Redis
    if docker-compose exec redis redis-cli ping | grep -q "PONG" &> /dev/null; then
        log_info "✓ Redis is healthy"
    else
        log_error "✗ Redis is not healthy"
        all_healthy=false
    fi
    
    # Check Integration Service
    if curl -f http://localhost:8080/health &> /dev/null; then
        log_info "✓ Integration Service is healthy"
    else
        log_error "✗ Integration Service is not healthy"
        all_healthy=false
    fi
    
    # Check Worker
    if docker-compose ps worker | grep -q "Up" &> /dev/null; then
        log_info "✓ Worker is running"
    else
        log_error "✗ Worker is not running"
        all_healthy=false
    fi
    
    if [ "$all_healthy" = true ]; then
        log_info "All services are healthy!"
        return 0
    else
        log_error "Some services are not healthy. Check logs for details."
        return 1
    fi
}

show_status() {
    log_info "Service Status:"
    docker-compose ps
    
    echo ""
    log_info "Service URLs:"
    echo "  Integration API: http://localhost:8080"
    echo "  Metrics: http://localhost:9090/metrics"
    echo "  Health Check: http://localhost:8080/health"
    echo "  PostgreSQL: localhost:5434"
    echo "  Redis: localhost:6381"
    
    echo ""
    log_info "API Endpoints:"
    echo "  Webhook: POST http://localhost:8080/webhook/litellm/usage"
    echo "  Customer Mapping: POST http://localhost:8080/customers/mapping"
    echo "  Metrics: GET http://localhost:8080/metrics"
    
    echo ""
    log_info "Configuration:"
    echo "  LiteLLM URL: ${LITELLM_API_URL:-http://localhost:4000}"
    echo "  Lago URL: ${LAGO_API_URL:-http://localhost:3000}"
}

show_logs() {
    local service=${1:-""}
    if [ -n "$service" ]; then
        docker-compose logs -f "$service"
    else
        docker-compose logs -f
    fi
}

test_integration() {
    log_info "Testing integration..."
    
    # Test health endpoint
    log_info "Testing health endpoint..."
    if curl -f http://localhost:8080/health; then
        log_info "✓ Health check passed"
    else
        log_error "✗ Health check failed"
        return 1
    fi
    
    # Test metrics endpoint
    log_info "Testing metrics endpoint..."
    if curl -f http://localhost:8080/metrics; then
        log_info "✓ Metrics endpoint accessible"
    else
        log_error "✗ Metrics endpoint failed"
        return 1
    fi
    
    # Test customer mapping retrieval
    log_info "Testing customer mapping..."
    if curl -f -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
            http://localhost:8080/customers/demo-customer-1/mapping; then
        log_info "✓ Customer mapping test passed"
    else
        log_error "✗ Customer mapping test failed"
        return 1
    fi
    
    log_info "Integration tests completed successfully!"
}

stop_services() {
    log_info "Stopping services..."
    docker-compose down
}

restart_services() {
    log_info "Restarting services..."
    docker-compose restart
}

update_services() {
    log_info "Updating services..."
    create_backup true
    docker-compose build --no-cache
    docker-compose up -d
    check_service_health
}

cleanup() {
    log_warn "This will remove all containers, volumes, and data. Are you sure? (y/N)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        log_info "Cleaning up..."
        docker-compose down -v --remove-orphans
        docker system prune -f
        log_info "Cleanup completed."
    else
        log_info "Cleanup cancelled."
    fi
}

show_help() {
    echo "LiteLLM-Lago Integration Service Deployment Script"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  deploy     Deploy all services (default)"
    echo "  status     Show service status and URLs"
    echo "  logs       Show logs for all services"
    echo "  logs <svc> Show logs for specific service"
    echo "  stop       Stop all services"
    echo "  restart    Restart all services"
    echo "  update     Update services to latest versions"
    echo "  backup     Create backup of database and config"
    echo "  cleanup    Remove all containers and data"
    echo "  health     Check service health"
    echo "  test       Run integration tests"
    echo "  setup      Setup customer mappings"
    echo "  help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 deploy"
    echo "  $0 logs integration-service"
    echo "  $0 test"
    echo "  $0 setup"
}

# Main script logic
case "${1:-deploy}" in
    "deploy")
        check_prerequisites
        create_backup false
        deploy_services
        setup_customer_mappings
        show_status
        ;;
    "status")
        show_status
        ;;
    "logs")
        show_logs "$2"
        ;;
    "stop")
        stop_services
        ;;
    "restart")
        restart_services
        ;;
    "update")
        check_prerequisites
        update_services
        show_status
        ;;
    "backup")
        create_backup true
        ;;
    "cleanup")
        cleanup
        ;;
    "health")
        check_service_health
        ;;
    "test")
        test_integration
        ;;
    "setup")
        setup_customer_mappings
        ;;
    "help"|"-h"|"--help")
        show_help
        ;;
    *)
        log_error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac