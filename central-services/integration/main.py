#!/usr/bin/env python3
"""
LiteLLM to Lago Integration Service
Handles webhooks from LiteLLM and forwards usage events to Lago billing system
"""

import os
import json
import asyncio
import logging
from datetime import datetime, timezone
from typing import Dict, Any, Optional, List
import asyncpg
import aioredis
import aiohttp
from fastapi import FastAPI, HTTPException, Request, BackgroundTasks, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, Field, validator
import uvicorn
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
from starlette.responses import Response
import hashlib
import hmac

# Configure logging
logging.basicConfig(
    level=getattr(logging, os.getenv("LOG_LEVEL", "INFO")),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Prometheus metrics
webhook_requests_total = Counter('webhook_requests_total', 'Total webhook requests', ['source', 'status'])
event_processing_duration = Histogram('event_processing_duration_seconds', 'Event processing duration')
lago_api_requests_total = Counter('lago_api_requests_total', 'Total Lago API requests', ['method', 'status'])
failed_events_total = Counter('failed_events_total', 'Total failed events', ['error_type'])
active_customers_gauge = Gauge('active_customers_total', 'Total active customers')
pending_events_gauge = Gauge('pending_events_total', 'Total pending events')

app = FastAPI(
    title="LiteLLM-Lago Integration Service",
    version="1.0.0",
    description="Integration service between LiteLLM and Lago billing system"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

security = HTTPBearer(auto_error=False)

class LiteLLMUsageEvent(BaseModel):
    """Usage event from LiteLLM"""
    id: str
    user: str
    model: str
    prompt_tokens: int = 0
    completion_tokens: int = 0
    total_tokens: int = 0
    spend: float = 0.0
    startTime: datetime
    endTime: datetime
    api_key: Optional[str] = None
    request_id: Optional[str] = None
    
    @validator('startTime', 'endTime', pre=True)
    def parse_datetime(cls, v):
        if isinstance(v, str):
            return datetime.fromisoformat(v.replace('Z', '+00:00'))
        return v

class LagoUsageEvent(BaseModel):
    """Usage event for Lago"""
    transaction_id: str
    external_customer_id: str
    code: str = "ai_usage"
    timestamp: datetime
    properties: Dict[str, Any]

class CustomerMapping(BaseModel):
    """Customer mapping configuration"""
    litellm_customer_id: str
    lago_customer_id: str
    lago_organization_id: str
    billing_plan: str = "ai_basic"
    is_active: bool = True

class Config:
    """Application configuration"""
    def __init__(self):
        self.database_url = os.getenv("DATABASE_URL", "postgresql://integration:password@localhost:5432/integration")
        self.redis_url = os.getenv("REDIS_URL", "redis://localhost:6379")
        
        # LiteLLM Configuration
        self.litellm_api_url = os.getenv("LITELLM_API_URL", "http://localhost:4000")
        self.litellm_master_key = os.getenv("LITELLM_MASTER_KEY", "")
        
        # Lago Configuration
        self.lago_api_url = os.getenv("LAGO_API_URL", "http://localhost:3000")
        self.lago_api_key = os.getenv("LAGO_API_KEY", "")
        self.lago_webhook_secret = os.getenv("LAGO_WEBHOOK_SECRET", "")
        
        # Service Configuration
        self.webhook_timeout = int(os.getenv("WEBHOOK_TIMEOUT", "30"))
        self.max_retries = int(os.getenv("MAX_RETRIES", "3"))
        self.retry_delay = int(os.getenv("RETRY_DELAY", "60"))
        self.batch_size = int(os.getenv("BATCH_SIZE", "100"))
        
        # Monitoring
        self.enable_metrics = os.getenv("ENABLE_METRICS", "true").lower() == "true"
        self.metrics_port = int(os.getenv("METRICS_PORT", "9090"))

config = Config()

class DatabaseManager:
    """Manages database connections and operations"""
    
    def __init__(self):
        self.pool: Optional[asyncpg.Pool] = None
    
    async def initialize(self):
        """Initialize database connection pool"""
        try:
            self.pool = await asyncpg.create_pool(
                config.database_url,
                min_size=2,
                max_size=20,
                command_timeout=60
            )
            logger.info("Database connection pool initialized")
        except Exception as e:
            logger.error(f"Failed to initialize database pool: {e}")
            raise
    
    async def close(self):
        """Close database connection pool"""
        if self.pool:
            await self.pool.close()
            logger.info("Database connection pool closed")
    
    async def get_customer_mapping(self, litellm_customer_id: str) -> Optional[CustomerMapping]:
        """Get customer mapping from database"""
        async with self.pool.acquire() as conn:
            row = await conn.fetchrow(
                "SELECT * FROM customer_mappings WHERE litellm_customer_id = $1 AND is_active = true",
                litellm_customer_id
            )
            return CustomerMapping(**dict(row)) if row else None
    
    async def create_customer_mapping(self, mapping: CustomerMapping) -> bool:
        """Create customer mapping"""
        async with self.pool.acquire() as conn:
            try:
                await conn.execute(
                    """
                    INSERT INTO customer_mappings 
                    (litellm_customer_id, lago_customer_id, lago_organization_id, billing_plan, is_active)
                    VALUES ($1, $2, $3, $4, $5)
                    ON CONFLICT (litellm_customer_id) DO UPDATE SET
                        lago_customer_id = EXCLUDED.lago_customer_id,
                        lago_organization_id = EXCLUDED.lago_organization_id,
                        billing_plan = EXCLUDED.billing_plan,
                        is_active = EXCLUDED.is_active,
                        updated_at = NOW()
                    """,
                    mapping.litellm_customer_id,
                    mapping.lago_customer_id,
                    mapping.lago_organization_id,
                    mapping.billing_plan,
                    mapping.is_active
                )
                return True
            except Exception as e:
                logger.error(f"Failed to create customer mapping: {e}")
                return False
    
    async def queue_event(self, event: LagoUsageEvent, customer_mapping: CustomerMapping) -> str:
        """Queue event for processing"""
        async with self.pool.acquire() as conn:
            event_id = await conn.fetchval(
                """
                INSERT INTO event_queue 
                (transaction_id, external_customer_id, event_data, customer_mapping_id, status)
                VALUES ($1, $2, $3, $4, 'pending')
                RETURNING id
                """,
                event.transaction_id,
                event.external_customer_id,
                json.dumps(event.dict()),
                customer_mapping.litellm_customer_id
            )
            return str(event_id)
    
    async def update_event_status(self, event_id: str, status: str, error_message: str = None):
        """Update event processing status"""
        async with self.pool.acquire() as conn:
            await conn.execute(
                """
                UPDATE event_queue 
                SET status = $2, processed_at = NOW(), error_message = $3, retry_count = retry_count + 1
                WHERE id = $1
                """,
                event_id, status, error_message
            )
    
    async def get_pending_events(self, limit: int = None) -> List[Dict[str, Any]]:
        """Get pending events for processing"""
        limit = limit or config.batch_size
        async with self.pool.acquire() as conn:
            rows = await conn.fetch(
                """
                SELECT id, transaction_id, external_customer_id, event_data, customer_mapping_id, retry_count
                FROM event_queue 
                WHERE status = 'pending' OR (status = 'failed' AND retry_count < $1)
                ORDER BY created_at ASC
                LIMIT $2
                """,
                config.max_retries, limit
            )
            return [dict(row) for row in rows]
    
    async def get_metrics(self) -> Dict[str, Any]:
        """Get processing metrics"""
        async with self.pool.acquire() as conn:
            stats = await conn.fetchrow("""
                SELECT 
                    COUNT(*) as total_events,
                    COUNT(*) FILTER (WHERE status = 'completed') as completed_events,
                    COUNT(*) FILTER (WHERE status = 'failed') as failed_events,
                    COUNT(*) FILTER (WHERE status = 'pending') as pending_events,
                    COUNT(DISTINCT customer_mapping_id) as active_customers
                FROM event_queue
                WHERE created_at >= NOW() - INTERVAL '24 hours'
            """)
            return dict(stats)

class LagoClient:
    """Client for interacting with Lago API"""
    
    def __init__(self):
        self.session: Optional[aiohttp.ClientSession] = None
    
    async def initialize(self):
        """Initialize HTTP session"""
        self.session = aiohttp.ClientSession(
            headers={
                "Authorization": f"Bearer {config.lago_api_key}",
                "Content-Type": "application/json"
            },
            timeout=aiohttp.ClientTimeout(total=config.webhook_timeout)
        )
    
    async def close(self):
        """Close HTTP session"""
        if self.session:
            await self.session.close()
    
    async def send_usage_event(self, event: LagoUsageEvent) -> bool:
        """Send usage event to Lago"""
        try:
            url = f"{config.lago_api_url}/api/v1/events"
            payload = {
                "event": {
                    "transaction_id": event.transaction_id,
                    "external_customer_id": event.external_customer_id,
                    "code": event.code,
                    "timestamp": event.timestamp.isoformat(),
                    "properties": event.properties
                }
            }
            
            async with self.session.post(url, json=payload) as response:
                lago_api_requests_total.labels(method='POST', status=response.status).inc()
                
                if response.status == 200:
                    logger.info(f"Successfully sent event {event.transaction_id} to Lago")
                    return True
                else:
                    error_text = await response.text()
                    logger.error(f"Failed to send event to Lago: {response.status} - {error_text}")
                    failed_events_total.labels(error_type='lago_api_error').inc()
                    return False
                    
        except Exception as e:
            logger.error(f"Error sending event to Lago: {e}")
            failed_events_total.labels(error_type='network_error').inc()
            return False

# Global instances
db_manager = DatabaseManager()
lago_client = LagoClient()
redis_client: Optional[aioredis.Redis] = None

def verify_webhook_signature(payload: bytes, signature: str) -> bool:
    """Verify webhook signature"""
    if not config.lago_webhook_secret:
        return True  # Skip verification if no secret configured
    
    expected_signature = hmac.new(
        config.lago_webhook_secret.encode(),
        payload,
        hashlib.sha256
    ).hexdigest()
    
    return hmac.compare_digest(f"sha256={expected_signature}", signature)

def convert_to_lago_event(usage_event: LiteLLMUsageEvent, customer_mapping: CustomerMapping) -> LagoUsageEvent:
    """Convert LiteLLM usage event to Lago event format"""
    return LagoUsageEvent(
        transaction_id=f"litellm_{usage_event.id}_{int(usage_event.startTime.timestamp())}",
        external_customer_id=customer_mapping.lago_customer_id,
        timestamp=usage_event.startTime,
        properties={
            "model": usage_event.model,
            "input_tokens": usage_event.prompt_tokens,
            "output_tokens": usage_event.completion_tokens,
            "total_tokens": usage_event.total_tokens,
            "cost_usd": usage_event.spend,
            "duration_seconds": (usage_event.endTime - usage_event.startTime).total_seconds(),
            "litellm_customer_id": usage_event.user,
            "request_id": usage_event.request_id or usage_event.id,
            "api_key_hash": hashlib.sha256((usage_event.api_key or "").encode()).hexdigest()[:16]
        }
    )

async def process_usage_event(usage_event: LiteLLMUsageEvent) -> bool:
    """Process a single usage event"""
    with event_processing_duration.time():
        try:
            # Get customer mapping
            customer_mapping = await db_manager.get_customer_mapping(usage_event.user)
            if not customer_mapping:
                logger.warning(f"No customer mapping found for: {usage_event.user}")
                failed_events_total.labels(error_type='no_customer_mapping').inc()
                return False
            
            # Convert to Lago event format
            lago_event = convert_to_lago_event(usage_event, customer_mapping)
            
            # Queue the event
            event_id = await db_manager.queue_event(lago_event, customer_mapping)
            
            # Try to send immediately
            success = await lago_client.send_usage_event(lago_event)
            
            # Update status
            if success:
                await db_manager.update_event_status(event_id, "completed")
                webhook_requests_total.labels(source='litellm', status='success').inc()
            else:
                await db_manager.update_event_status(event_id, "failed", "Failed to send to Lago")
                webhook_requests_total.labels(source='litellm', status='failed').inc()
            
            return success
            
        except Exception as e:
            logger.error(f"Error processing usage event: {e}")
            failed_events_total.labels(error_type='processing_error').inc()
            webhook_requests_total.labels(source='litellm', status='error').inc()
            return False

@app.on_event("startup")
async def startup_event():
    """Initialize services on startup"""
    global redis_client
    
    await db_manager.initialize()
    await lago_client.initialize()
    
    # Initialize Redis
    redis_client = aioredis.from_url(config.redis_url)
    
    # Start background task for processing queued events
    asyncio.create_task(process_queued_events())
    
    # Start metrics update task
    if config.enable_metrics:
        asyncio.create_task(update_metrics())
    
    logger.info("Integration service started successfully")

@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    await db_manager.close()
    await lago_client.close()
    
    if redis_client:
        await redis_client.close()
    
    logger.info("Integration service shutdown complete")

@app.post("/webhook/litellm/usage")
async def handle_litellm_webhook(request: Request, background_tasks: BackgroundTasks):
    """Handle usage events from LiteLLM"""
    try:
        # Get request body and signature
        body = await request.body()
        signature = request.headers.get("X-Webhook-Signature", "")
        
        # Verify signature
        if not verify_webhook_signature(body, signature):
            webhook_requests_total.labels(source='litellm', status='unauthorized').inc()
            raise HTTPException(status_code=401, detail="Invalid webhook signature")
        
        # Parse payload
        payload = json.loads(body)
        logger.info(f"Received LiteLLM webhook: {json.dumps(payload, default=str)}")
        
        # Parse usage event
        usage_event = LiteLLMUsageEvent(**payload)
        
        # Process in background
        background_tasks.add_task(process_usage_event, usage_event)
        
        return {"status": "accepted", "message": "Event queued for processing"}
        
    except Exception as e:
        logger.error(f"Error handling LiteLLM webhook: {e}")
        webhook_requests_total.labels(source='litellm', status='error').inc()
        raise HTTPException(status_code=400, detail=str(e))

@app.post("/customers/mapping")
async def create_customer_mapping(mapping: CustomerMapping, credentials: HTTPAuthorizationCredentials = Depends(security)):
    """Create or update customer mapping"""
    # Verify authorization (implement your auth logic here)
    if not credentials or credentials.credentials != config.litellm_master_key:
        raise HTTPException(status_code=401, detail="Unauthorized")
    
    success = await db_manager.create_customer_mapping(mapping)
    if success:
        return {"status": "success", "message": "Customer mapping created/updated"}
    else:
        raise HTTPException(status_code=500, detail="Failed to create customer mapping")

@app.get("/customers/{customer_id}/mapping")
async def get_customer_mapping(customer_id: str, credentials: HTTPAuthorizationCredentials = Depends(security)):
    """Get customer mapping"""
    if not credentials or credentials.credentials != config.litellm_master_key:
        raise HTTPException(status_code=401, detail="Unauthorized")
    
    mapping = await db_manager.get_customer_mapping(customer_id)
    if mapping:
        return mapping
    else:
        raise HTTPException(status_code=404, detail="Customer mapping not found")

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    try:
        # Check database connection
        async with db_manager.pool.acquire() as conn:
            await conn.fetchval("SELECT 1")
        
        # Check Lago API connectivity
        async with lago_client.session.get(f"{config.lago_api_url}/health") as response:
            lago_healthy = response.status == 200
        
        # Check Redis connectivity
        redis_healthy = await redis_client.ping()
        
        return {
            "status": "healthy",
            "database": "connected",
            "lago_api": "connected" if lago_healthy else "disconnected",
            "redis": "connected" if redis_healthy else "disconnected",
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        raise HTTPException(status_code=503, detail="Service unhealthy")

@app.get("/metrics")
async def get_metrics():
    """Get processing metrics"""
    try:
        metrics = await db_manager.get_metrics()
        return metrics
    except Exception as e:
        logger.error(f"Error getting metrics: {e}")
        raise HTTPException(status_code=500, detail="Failed to get metrics")

@app.get("/metrics/prometheus")
async def prometheus_metrics():
    """Prometheus metrics endpoint"""
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

async def process_queued_events():
    """Background task to process queued events"""
    while True:
        try:
            await asyncio.sleep(config.retry_delay)
            
            pending_events = await db_manager.get_pending_events()
            logger.info(f"Processing {len(pending_events)} pending events")
            
            for event_data in pending_events:
                try:
                    event = LagoUsageEvent(**json.loads(event_data["event_data"]))
                    success = await lago_client.send_usage_event(event)
                    
                    if success:
                        await db_manager.update_event_status(event_data["id"], "completed")
                    else:
                        retry_count = event_data["retry_count"] + 1
                        if retry_count >= config.max_retries:
                            await db_manager.update_event_status(
                                event_data["id"], 
                                "failed", 
                                f"Max retries ({config.max_retries}) exceeded"
                            )
                        else:
                            await db_manager.update_event_status(
                                event_data["id"], 
                                "pending", 
                                f"Retry {retry_count}/{config.max_retries}"
                            )
                
                except Exception as e:
                    logger.error(f"Error processing queued event {event_data['id']}: {e}")
                    
        except Exception as e:
            logger.error(f"Error in background processing task: {e}")

async def update_metrics():
    """Background task to update Prometheus metrics"""
    while True:
        try:
            await asyncio.sleep(60)  # Update every minute
            
            metrics = await db_manager.get_metrics()
            active_customers_gauge.set(metrics.get('active_customers', 0))
            pending_events_gauge.set(metrics.get('pending_events', 0))
            
        except Exception as e:
            logger.error(f"Error updating metrics: {e}")

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=int(os.getenv("PORT", "8080")),
        reload=False,
        log_level=config.LOG_LEVEL.lower() if hasattr(config, 'LOG_LEVEL') else "info"
    )