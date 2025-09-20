#!/usr/bin/env python3
"""
Background Worker for LiteLLM-Lago Integration
Processes queued events and handles retry logic
"""

import os
import json
import asyncio
import logging
from datetime import datetime, timezone
from typing import Dict, Any, List
import asyncpg
import aioredis
import aiohttp
from dataclasses import dataclass
import signal
import sys

# Configure logging
logging.basicConfig(
    level=getattr(logging, os.getenv("LOG_LEVEL", "INFO")),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@dataclass
class WorkerConfig:
    """Worker configuration"""
    database_url: str = os.getenv("DATABASE_URL", "postgresql://integration:password@localhost:5432/integration")
    redis_url: str = os.getenv("REDIS_URL", "redis://localhost:6379")
    lago_api_url: str = os.getenv("LAGO_API_URL", "http://localhost:3000")
    lago_api_key: str = os.getenv("LAGO_API_KEY", "")
    max_retries: int = int(os.getenv("MAX_RETRIES", "3"))
    retry_delay: int = int(os.getenv("RETRY_DELAY", "60"))
    batch_size: int = int(os.getenv("BATCH_SIZE", "100"))
    webhook_timeout: int = int(os.getenv("WEBHOOK_TIMEOUT", "30"))
    worker_concurrency: int = int(os.getenv("WORKER_CONCURRENCY", "10"))

class EventProcessor:
    """Processes events from the queue"""
    
    def __init__(self, config: WorkerConfig):
        self.config = config
        self.db_pool: Optional[asyncpg.Pool] = None
        self.redis_client: Optional[aioredis.Redis] = None
        self.http_session: Optional[aiohttp.ClientSession] = None
        self.running = True
        
    async def initialize(self):
        """Initialize connections"""
        try:
            # Initialize database pool
            self.db_pool = await asyncpg.create_pool(
                self.config.database_url,
                min_size=2,
                max_size=self.config.worker_concurrency + 2,
                command_timeout=60
            )
            
            # Initialize Redis client
            self.redis_client = aioredis.from_url(self.config.redis_url)
            
            # Initialize HTTP session
            self.http_session = aiohttp.ClientSession(
                headers={
                    "Authorization": f"Bearer {self.config.lago_api_key}",
                    "Content-Type": "application/json"
                },
                timeout=aiohttp.ClientTimeout(total=self.config.webhook_timeout)
            )
            
            logger.info("Event processor initialized successfully")
            
        except Exception as e:
            logger.error(f"Failed to initialize event processor: {e}")
            raise
    
    async def close(self):
        """Close connections"""
        if self.db_pool:
            await self.db_pool.close()
        
        if self.redis_client:
            await self.redis_client.close()
        
        if self.http_session:
            await self.http_session.close()
        
        logger.info("Event processor closed")
    
    async def get_pending_events(self, limit: int = None) -> List[Dict[str, Any]]:
        """Get pending events from database"""
        limit = limit or self.config.batch_size
        
        async with self.db_pool.acquire() as conn:
            rows = await conn.fetch(
                """
                SELECT id, transaction_id, external_customer_id, event_data, 
                       customer_mapping_id, retry_count, created_at
                FROM event_queue 
                WHERE status = 'pending' 
                   OR (status = 'failed' AND retry_count < $1 AND 
                       last_retry_at < NOW() - INTERVAL '%s seconds')
                ORDER BY created_at ASC
                LIMIT $2
                """,
                self.config.max_retries,
                self.config.retry_delay,
                limit
            )
            return [dict(row) for row in rows]
    
    async def update_event_status(self, event_id: str, status: str, error_message: str = None):
        """Update event status in database"""
        async with self.db_pool.acquire() as conn:
            await conn.execute(
                """
                UPDATE event_queue 
                SET status = $2, 
                    processed_at = CASE WHEN $2 = 'completed' THEN NOW() ELSE processed_at END,
                    last_retry_at = NOW(),
                    error_message = $3, 
                    retry_count = retry_count + 1
                WHERE id = $1
                """,
                event_id, status, error_message
            )
    
    async def send_event_to_lago(self, event_data: Dict[str, Any]) -> bool:
        """Send event to Lago API"""
        try:
            event = json.loads(event_data["event_data"])
            
            url = f"{self.config.lago_api_url}/api/v1/events"
            payload = {
                "event": {
                    "transaction_id": event["transaction_id"],
                    "external_customer_id": event["external_customer_id"],
                    "code": event["code"],
                    "timestamp": event["timestamp"],
                    "properties": event["properties"]
                }
            }
            
            async with self.http_session.post(url, json=payload) as response:
                if response.status == 200:
                    logger.info(f"Successfully sent event {event['transaction_id']} to Lago")
                    return True
                else:
                    error_text = await response.text()
                    logger.error(f"Failed to send event to Lago: {response.status} - {error_text}")
                    return False
                    
        except Exception as e:
            logger.error(f"Error sending event to Lago: {e}")
            return False
    
    async def process_event(self, event_data: Dict[str, Any]) -> bool:
        """Process a single event"""
        event_id = event_data["id"]
        retry_count = event_data["retry_count"]
        
        try:
            logger.debug(f"Processing event {event_id} (retry {retry_count})")
            
            # Send to Lago
            success = await self.send_event_to_lago(event_data)
            
            if success:
                await self.update_event_status(event_id, "completed")
                logger.info(f"Event {event_id} processed successfully")
                return True
            else:
                # Check if we should retry
                if retry_count >= self.config.max_retries:
                    await self.update_event_status(
                        event_id, 
                        "failed", 
                        f"Max retries ({self.config.max_retries}) exceeded"
                    )
                    logger.error(f"Event {event_id} failed permanently after {retry_count} retries")
                else:
                    await self.update_event_status(
                        event_id, 
                        "pending", 
                        f"Retry {retry_count + 1}/{self.config.max_retries}"
                    )
                    logger.warning(f"Event {event_id} failed, will retry ({retry_count + 1}/{self.config.max_retries})")
                
                return False
                
        except Exception as e:
            logger.error(f"Error processing event {event_id}: {e}")
            
            # Update status as failed if max retries exceeded
            if retry_count >= self.config.max_retries:
                await self.update_event_status(event_id, "failed", str(e))
            else:
                await self.update_event_status(event_id, "pending", str(e))
            
            return False
    
    async def process_batch(self, events: List[Dict[str, Any]]) -> Dict[str, int]:
        """Process a batch of events concurrently"""
        if not events:
            return {"processed": 0, "succeeded": 0, "failed": 0}
        
        logger.info(f"Processing batch of {len(events)} events")
        
        # Create semaphore to limit concurrency
        semaphore = asyncio.Semaphore(self.config.worker_concurrency)
        
        async def process_with_semaphore(event_data):
            async with semaphore:
                return await self.process_event(event_data)
        
        # Process events concurrently
        results = await asyncio.gather(
            *[process_with_semaphore(event) for event in events],
            return_exceptions=True
        )
        
        # Count results
        succeeded = sum(1 for result in results if result is True)
        failed = len(events) - succeeded
        
        logger.info(f"Batch processed: {succeeded} succeeded, {failed} failed")
        
        return {
            "processed": len(events),
            "succeeded": succeeded,
            "failed": failed
        }
    
    async def run_processing_loop(self):
        """Main processing loop"""
        logger.info("Starting event processing loop")
        
        while self.running:
            try:
                # Get pending events
                events = await self.get_pending_events()
                
                if events:
                    # Process batch
                    results = await self.process_batch(events)
                    
                    # Log statistics
                    logger.info(f"Processing cycle complete: {results}")
                    
                    # Update Redis metrics
                    await self.update_metrics(results)
                else:
                    logger.debug("No pending events found")
                
                # Wait before next cycle
                await asyncio.sleep(self.config.retry_delay)
                
            except Exception as e:
                logger.error(f"Error in processing loop: {e}")
                await asyncio.sleep(10)  # Short delay on error
    
    async def update_metrics(self, results: Dict[str, int]):
        """Update metrics in Redis"""
        try:
            timestamp = datetime.now(timezone.utc).isoformat()
            
            # Store processing statistics
            await self.redis_client.hset(
                "worker:metrics",
                mapping={
                    "last_run": timestamp,
                    "events_processed": results["processed"],
                    "events_succeeded": results["succeeded"],
                    "events_failed": results["failed"]
                }
            )
            
            # Increment counters
            await self.redis_client.hincrby("worker:counters", "total_processed", results["processed"])
            await self.redis_client.hincrby("worker:counters", "total_succeeded", results["succeeded"])
            await self.redis_client.hincrby("worker:counters", "total_failed", results["failed"])
            
        except Exception as e:
            logger.error(f"Error updating metrics: {e}")
    
    async def get_queue_stats(self) -> Dict[str, Any]:
        """Get queue statistics"""
        async with self.db_pool.acquire() as conn:
            stats = await conn.fetchrow("""
                SELECT 
                    COUNT(*) as total_events,
                    COUNT(*) FILTER (WHERE status = 'pending') as pending_events,
                    COUNT(*) FILTER (WHERE status = 'completed') as completed_events,
                    COUNT(*) FILTER (WHERE status = 'failed') as failed_events,
                    COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '1 hour') as events_last_hour,
                    COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '24 hours') as events_last_day
                FROM event_queue
            """)
            return dict(stats)
    
    def stop(self):
        """Stop the processing loop"""
        logger.info("Stopping event processor...")
        self.running = False

class WorkerManager:
    """Manages the worker process"""
    
    def __init__(self):
        self.config = WorkerConfig()
        self.processor = EventProcessor(self.config)
        self.stats_task = None
        
    async def start(self):
        """Start the worker"""
        logger.info("Starting LiteLLM-Lago integration worker")
        
        # Initialize processor
        await self.processor.initialize()
        
        # Start statistics reporting task
        self.stats_task = asyncio.create_task(self.report_stats())
        
        # Start main processing loop
        await self.processor.run_processing_loop()
    
    async def stop(self):
        """Stop the worker"""
        logger.info("Stopping worker...")
        
        # Stop processor
        self.processor.stop()
        
        # Cancel stats task
        if self.stats_task:
            self.stats_task.cancel()
            try:
                await self.stats_task
            except asyncio.CancelledError:
                pass
        
        # Close processor
        await self.processor.close()
        
        logger.info("Worker stopped")
    
    async def report_stats(self):
        """Periodically report queue statistics"""
        while True:
            try:
                await asyncio.sleep(300)  # Report every 5 minutes
                
                stats = await self.processor.get_queue_stats()
                logger.info(f"Queue stats: {stats}")
                
                # Store stats in Redis
                await self.processor.redis_client.hset(
                    "worker:queue_stats",
                    mapping={
                        "timestamp": datetime.now(timezone.utc).isoformat(),
                        **{k: str(v) for k, v in stats.items()}
                    }
                )
                
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error reporting stats: {e}")

async def main():
    """Main function"""
    worker_manager = WorkerManager()
    
    # Setup signal handlers
    def signal_handler(signum, frame):
        logger.info(f"Received signal {signum}")
        asyncio.create_task(worker_manager.stop())
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    try:
        await worker_manager.start()
    except KeyboardInterrupt:
        logger.info("Received keyboard interrupt")
    except Exception as e:
        logger.error(f"Worker error: {e}")
        sys.exit(1)
    finally:
        await worker_manager.stop()

if __name__ == "__main__":
    asyncio.run(main())