#!/usr/bin/env python3
"""
LiteLLM Webhook Handler for Lago Integration
Processes usage events and forwards them to Lago billing system
"""

import os
import json
import asyncio
import logging
from datetime import datetime, timezone
from typing import Dict, Any, Optional
import asyncpg
import aiohttp
from fastapi import FastAPI, HTTPException, Request, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import uvicorn

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = FastAPI(title="LiteLLM Webhook Handler", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class UsageEvent(BaseModel):
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
    
class LagoEvent(BaseModel):
    """Event format for Lago billing system"""
    transaction_id: str
    external_customer_id: str
    code: str = "ai_usage"
    timestamp: datetime
    properties: Dict[str, Any]

class WebhookConfig:
    """Configuration for webhook processing"""
    def __init__(self):
        self.database_url = os.getenv("DATABASE_URL", "postgresql://litellm:password@localhost:5432/litellm")
        self.lago_api_url = os.getenv("LAGO_API_URL", "http://lago:3000")
        self.lago_api_key = os.getenv("LAGO_API_KEY", "")
        self.webhook_secret = os.getenv("LAGO_WEBHOOK_SECRET", "")
        self.max_retries = int(os.getenv("MAX_RETRIES", "3"))
        self.retry_delay = int(os.getenv("RETRY_DELAY", "60"))

config = WebhookConfig()

class DatabaseManager:
    """Manages database connections and operations"""
    
    def __init__(self):
        self.pool: Optional[asyncpg.Pool] = None
    
    async def initialize(self):
        """Initialize database connection pool"""
        try:
            self.pool = await asyncpg.create_pool(
                config.database_url,
                min_size=1,
                max_size=10,
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
    
    async def get_customer_config(self, customer_id: str) -> Optional[Dict[str, Any]]:
        """Get customer configuration from database"""
        async with self.pool.acquire() as conn:
            row = await conn.fetchrow(
                "SELECT * FROM customer_configs WHERE customer_id = $1 AND is_active = true",
                customer_id
            )
            return dict(row) if row else None
    
    async def queue_webhook_event(self, event_type: str, customer_id: str, payload: Dict[str, Any]) -> str:
        """Queue webhook event for processing"""
        async with self.pool.acquire() as conn:
            event_id = await conn.fetchval(
                "SELECT queue_webhook_event($1, $2, $3)",
                event_type, customer_id, json.dumps(payload)
            )
            return str(event_id)
    
    async def update_webhook_status(self, event_id: str, status: str, error_message: str = None):
        """Update webhook event status"""
        async with self.pool.acquire() as conn:
            await conn.execute(
                """
                UPDATE webhook_events 
                SET status = $2, processed_at = NOW(), error_message = $3
                WHERE id = $1
                """,
                event_id, status, error_message
            )
    
    async def get_pending_events(self, limit: int = 100) -> list:
        """Get pending webhook events for retry processing"""
        async with self.pool.acquire() as conn:
            rows = await conn.fetch(
                """
                SELECT id, event_type, customer_id, payload, retry_count
                FROM webhook_events 
                WHERE status = 'pending' OR (status = 'failed' AND retry_count < $1)
                ORDER BY created_at ASC
                LIMIT $2
                """,
                config.max_retries, limit
            )
            return [dict(row) for row in rows]

db_manager = DatabaseManager()

class LagoClient:
    """Client for interacting with Lago billing API"""
    
    def __init__(self):
        self.session: Optional[aiohttp.ClientSession] = None
    
    async def initialize(self):
        """Initialize HTTP session"""
        self.session = aiohttp.ClientSession(
            headers={
                "Authorization": f"Bearer {config.lago_api_key}",
                "Content-Type": "application/json"
            },
            timeout=aiohttp.ClientTimeout(total=30)
        )
    
    async def close(self):
        """Close HTTP session"""
        if self.session:
            await self.session.close()
    
    async def send_usage_event(self, event: LagoEvent) -> bool:
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
                if response.status == 200:
                    logger.info(f"Successfully sent event {event.transaction_id} to Lago")
                    return True
                else:
                    error_text = await response.text()
                    logger.error(f"Failed to send event to Lago: {response.status} - {error_text}")
                    return False
                    
        except Exception as e:
            logger.error(f"Error sending event to Lago: {e}")
            return False

lago_client = LagoClient()

def convert_to_lago_event(usage_event: UsageEvent, customer_config: Dict[str, Any]) -> LagoEvent:
    """Convert LiteLLM usage event to Lago event format"""
    return LagoEvent(
        transaction_id=f"litellm_{usage_event.id}_{int(usage_event.startTime.timestamp())}",
        external_customer_id=customer_config["lago_organization_id"],
        timestamp=usage_event.startTime,
        properties={
            "model": usage_event.model,
            "input_tokens": usage_event.prompt_tokens,
            "output_tokens": usage_event.completion_tokens,
            "total_tokens": usage_event.total_tokens,
            "cost_usd": usage_event.spend,
            "duration_seconds": (usage_event.endTime - usage_event.startTime).total_seconds(),
            "customer_id": usage_event.user,
            "request_id": usage_event.request_id or usage_event.id
        }
    )

async def process_usage_event(usage_event: UsageEvent) -> bool:
    """Process a single usage event"""
    try:
        # Get customer configuration
        customer_config = await db_manager.get_customer_config(usage_event.user)
        if not customer_config:
            logger.warning(f"No configuration found for customer: {usage_event.user}")
            return False
        
        if not customer_config.get("lago_organization_id"):
            logger.warning(f"No Lago organization ID for customer: {usage_event.user}")
            return False
        
        # Convert to Lago event format
        lago_event = convert_to_lago_event(usage_event, customer_config)
        
        # Queue the event for processing
        event_id = await db_manager.queue_webhook_event(
            "usage_event",
            usage_event.user,
            lago_event.dict()
        )
        
        # Try to send immediately
        success = await lago_client.send_usage_event(lago_event)
        
        # Update status
        if success:
            await db_manager.update_webhook_status(event_id, "completed")
        else:
            await db_manager.update_webhook_status(event_id, "failed", "Failed to send to Lago")
        
        return success
        
    except Exception as e:
        logger.error(f"Error processing usage event: {e}")
        return False

@app.on_event("startup")
async def startup_event():
    """Initialize services on startup"""
    await db_manager.initialize()
    await lago_client.initialize()
    
    # Start background task for retry processing
    asyncio.create_task(retry_failed_events())
    logger.info("Webhook handler started successfully")

@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    await db_manager.close()
    await lago_client.close()
    logger.info("Webhook handler shutdown complete")

@app.post("/webhook/usage")
async def handle_usage_webhook(request: Request, background_tasks: BackgroundTasks):
    """Handle usage events from LiteLLM"""
    try:
        payload = await request.json()
        logger.info(f"Received webhook payload: {json.dumps(payload, default=str)}")
        
        # Validate webhook signature if configured
        if config.webhook_secret:
            signature = request.headers.get("X-Webhook-Signature")
            if not signature:
                raise HTTPException(status_code=401, detail="Missing webhook signature")
            # Add signature validation logic here if needed
        
        # Parse usage event
        usage_event = UsageEvent(**payload)
        
        # Process in background
        background_tasks.add_task(process_usage_event, usage_event)
        
        return {"status": "accepted", "message": "Event queued for processing"}
        
    except Exception as e:
        logger.error(f"Error handling webhook: {e}")
        raise HTTPException(status_code=400, detail=str(e))

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
        
        return {
            "status": "healthy",
            "database": "connected",
            "lago_api": "connected" if lago_healthy else "disconnected",
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        raise HTTPException(status_code=503, detail="Service unhealthy")

@app.get("/metrics")
async def get_metrics():
    """Get processing metrics"""
    try:
        async with db_manager.pool.acquire() as conn:
            stats = await conn.fetchrow("""
                SELECT 
                    COUNT(*) as total_events,
                    COUNT(*) FILTER (WHERE status = 'completed') as completed_events,
                    COUNT(*) FILTER (WHERE status = 'failed') as failed_events,
                    COUNT(*) FILTER (WHERE status = 'pending') as pending_events
                FROM webhook_events
                WHERE created_at >= NOW() - INTERVAL '24 hours'
            """)
        
        return dict(stats)
    except Exception as e:
        logger.error(f"Error getting metrics: {e}")
        raise HTTPException(status_code=500, detail="Failed to get metrics")

async def retry_failed_events():
    """Background task to retry failed events"""
    while True:
        try:
            await asyncio.sleep(config.retry_delay)
            
            pending_events = await db_manager.get_pending_events()
            logger.info(f"Processing {len(pending_events)} pending events")
            
            for event in pending_events:
                try:
                    lago_event = LagoEvent(**event["payload"])
                    success = await lago_client.send_usage_event(lago_event)
                    
                    if success:
                        await db_manager.update_webhook_status(event["id"], "completed")
                    else:
                        retry_count = event["retry_count"] + 1
                        if retry_count >= config.max_retries:
                            await db_manager.update_webhook_status(
                                event["id"], 
                                "failed", 
                                f"Max retries ({config.max_retries}) exceeded"
                            )
                        else:
                            # Update retry count
                            async with db_manager.pool.acquire() as conn:
                                await conn.execute(
                                    "UPDATE webhook_events SET retry_count = $2, last_retry_at = NOW() WHERE id = $1",
                                    event["id"], retry_count
                                )
                
                except Exception as e:
                    logger.error(f"Error retrying event {event['id']}: {e}")
                    
        except Exception as e:
            logger.error(f"Error in retry background task: {e}")

if __name__ == "__main__":
    uvicorn.run(
        "webhook-handler:app",
        host="0.0.0.0",
        port=8000,
        reload=False,
        log_level="info"
    )