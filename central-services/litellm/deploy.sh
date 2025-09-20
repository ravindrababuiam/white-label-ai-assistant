#!/bin/bash

# LiteLLM Deployment Script
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env"

echo -e "${GREEN}🚀 Starting LiteLLM Deployment${NC}"

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
    "LITELLM_MASTER_KEY"
    "LITELLM_SALT_KEY"
    "UI_USERNAME"
    "UI_PASSWORD"
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
    exit 1
fi

# Create necessary directories
echo -e "${YELLOW}📁 Creating directories...${NC}"
mkdir -p logs
mkdir -p data/postgres

# Build webhook service
echo -e "${YELLOW}🔨 Building webhook service...${NC}"
cd webhook-service
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
max_attempts=30
attempt=0

while [ $attempt -lt $max_attempts ]; do
    if docker-compose ps | grep -q "healthy"; then
        healthy_count=$(docker-compose ps | grep -c "healthy" || true)
        total_services=4  # postgres, litellm, redis, webhook-service
        
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

# Test endpoints
echo -e "${YELLOW}🧪 Testing endpoints...${NC}"

# Test LiteLLM health
if curl -f -s http://localhost:4000/health > /dev/null; then
    echo -e "${GREEN}✅ LiteLLM is responding${NC}"
else
    echo -e "${RED}❌ LiteLLM health check failed${NC}"
fi

# Test webhook service health
if curl -f -s http://localhost:3001/health > /dev/null; then
    echo -e "${GREEN}✅ Webhook service is responding${NC}"
else
    echo -e "${RED}❌ Webhook service health check failed${NC}"
fi

# Display service information
echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
echo -e "${YELLOW}📋 Service Information:${NC}"
echo "  LiteLLM Proxy: http://localhost:4000"
echo "  LiteLLM UI: http://localhost:4000/ui"
echo "  Webhook Service: http://localhost:3001"
echo "  PostgreSQL: localhost:5432"
echo "  Redis: localhost:6379"
echo ""
echo -e "${YELLOW}📋 Default Credentials:${NC}"
echo "  UI Username: $(grep UI_USERNAME .env | cut -d'=' -f2)"
echo "  Master Key: $(grep LITELLM_MASTER_KEY .env | cut -d'=' -f2)"
echo ""
echo -e "${YELLOW}📋 Useful Commands:${NC}"
echo "  View logs: docker-compose logs -f"
echo "  Stop services: docker-compose down"
echo "  Restart services: docker-compose restart"
echo "  View status: docker-compose ps"