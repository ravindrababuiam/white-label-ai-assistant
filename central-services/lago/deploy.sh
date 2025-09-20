#!/bin/bash

# Lago Billing System Deployment Script
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env"

echo -e "${GREEN}🚀 Starting Lago Billing System Deployment${NC}"

# Check if .env file exists
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${YELLOW}⚠️  .env file not found. Creating from example...${NC}"
    cp .env.example .env
    echo -e "${RED}❌ Please configure .env file with your settings and run again${NC}"
    exit 1
fi

# Validate required environment variables
echo -e "${YELLOW}🔍 Validating environment configuration...${NC}"

required_vars=(
    "POSTGRES_PASSWORD"
    "SECRET_KEY_BASE"
    "ENCRYPTION_PRIMARY_KEY"
    "ENCRYPTION_DETERMINISTIC_KEY"
    "ENCRYPTION_KEY_DERIVATION_SALT"
)

missing_vars=()
for var in "${required_vars[@]}"; do
    if ! grep -q "^${var}=" "$ENV_FILE" || grep -q "^${var}=$" "$ENV_FILE" || grep -q "^${var}=your_" "$ENV_FILE"; then
        missing_vars+=("$var")
    fi
done

if [ ${#missing_vars[@]} -ne 0 ]; then
    echo -e "${RED}❌ Missing or incomplete environment variables:${NC}"
    printf '%s\n' "${missing_vars[@]}"
    echo -e "${RED}Please configure these variables in .env file${NC}"
    echo -e "${YELLOW}💡 Use the following commands to generate secure keys:${NC}"
    echo "SECRET_KEY_BASE: openssl rand -hex 64"
    echo "ENCRYPTION_PRIMARY_KEY: openssl rand -hex 32"
    echo "ENCRYPTION_DETERMINISTIC_KEY: openssl rand -hex 32"
    echo "ENCRYPTION_KEY_DERIVATION_SALT: openssl rand -hex 32"
    exit 1
fi

# Create necessary directories
echo -e "${YELLOW}📁 Creating directories...${NC}"
mkdir -p logs
mkdir -p storage
mkdir -p data/postgres
mkdir -p data/redis

# Build API integration service
echo -e "${YELLOW}🔨 Building API integration service...${NC}"
cd api-integration
npm install
npm run build
cd ..

# Pull latest images
echo -e "${YELLOW}📥 Pulling Docker images...${NC}"
docker-compose pull

# Stop existing containers
echo -e "${YELLOW}🛑 Stopping existing containers...${NC}"
docker-compose down

# Start services
echo -e "${YELLOW}🚀 Starting services...${NC}"
docker-compose up -d

# Wait for services to be healthy
echo -e "${YELLOW}⏳ Waiting for services to be healthy...${NC}"
max_attempts=60  # Lago takes longer to start
attempt=0

while [ $attempt -lt $max_attempts ]; do
    if docker-compose ps | grep -q "healthy"; then
        healthy_count=$(docker-compose ps | grep -c "healthy" || true)
        total_services=6  # postgres, redis, lago-api, lago-worker, lago-frontend, lago-api-integration
        
        if [ "$healthy_count" -eq "$total_services" ]; then
            echo -e "${GREEN}✅ All services are healthy${NC}"
            break
        fi
    fi
    
    attempt=$((attempt + 1))
    echo -e "${YELLOW}⏳ Attempt $attempt/$max_attempts - Waiting for services...${NC}"
    sleep 10
done

if [ $attempt -eq $max_attempts ]; then
    echo -e "${RED}❌ Services failed to become healthy within timeout${NC}"
    echo -e "${YELLOW}📋 Service status:${NC}"
    docker-compose ps
    echo -e "${YELLOW}📋 Service logs:${NC}"
    docker-compose logs --tail=20
    exit 1
fi

# Run database migrations
echo -e "${YELLOW}🗄️  Running database migrations...${NC}"
docker-compose exec lago-api bundle exec rails db:create db:migrate

# Test endpoints
echo -e "${YELLOW}🧪 Testing endpoints...${NC}"

# Test Lago API health
if curl -f -s http://localhost:3000/health > /dev/null; then
    echo -e "${GREEN}✅ Lago API is responding${NC}"
else
    echo -e "${RED}❌ Lago API health check failed${NC}"
fi

# Test Lago Frontend
if curl -f -s http://localhost:8080 > /dev/null; then
    echo -e "${GREEN}✅ Lago Frontend is responding${NC}"
else
    echo -e "${RED}❌ Lago Frontend health check failed${NC}"
fi

# Test API Integration service
if curl -f -s http://localhost:3002/health > /dev/null; then
    echo -e "${GREEN}✅ API Integration service is responding${NC}"
else
    echo -e "${RED}❌ API Integration service health check failed${NC}"
fi

# Setup default organization and billing metrics
echo -e "${YELLOW}⚙️  Setting up default billing configuration...${NC}"
if curl -f -s -X POST http://localhost:3002/api/organizations/setup > /dev/null; then
    echo -e "${GREEN}✅ Default billing configuration created${NC}"
else
    echo -e "${YELLOW}⚠️  Could not create default billing configuration (may already exist)${NC}"
fi

# Display service information
echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
echo -e "${YELLOW}📋 Service Information:${NC}"
echo "  Lago API: http://localhost:3000"
echo "  Lago Frontend: http://localhost:8080"
echo "  API Integration: http://localhost:3002"
echo "  PostgreSQL: localhost:5433"
echo "  Redis: localhost:6380"
echo ""
echo -e "${YELLOW}📋 API Endpoints:${NC}"
echo "  Organizations: http://localhost:3002/api/organizations"
echo "  Customers: http://localhost:3002/api/customers"
echo "  Billing: http://localhost:3002/api/billing"
echo "  Webhooks: http://localhost:3002/webhooks"
echo ""
echo -e "${YELLOW}📋 Useful Commands:${NC}"
echo "  View logs: docker-compose logs -f"
echo "  Stop services: docker-compose down"
echo "  Restart services: docker-compose restart"
echo "  View status: docker-compose ps"
echo "  Access Lago console: docker-compose exec lago-api bundle exec rails console"