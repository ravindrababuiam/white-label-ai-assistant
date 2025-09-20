# LiteLLM-Lago Integration Service

This service provides seamless integration between LiteLLM Proxy and Lago billing system, handling usage event processing, customer mapping, and billing automation for the white-label AI assistant platform.

## Features

- **Webhook Processing**: Receives and processes usage events from LiteLLM
- **Customer Mapping**: Maps LiteLLM customers to Lago billing entities
- **Event Queue**: Reliable event processing with retry mechanisms
- **Background Worker**: Asynchronous processing of billing events
- **Monitoring**: Comprehensive metrics and health checks
- **Error Handling**: Robust error handling with dead letter queues

## Architecture

```
LiteLLM → Webhook → Integration Service → Event Queue → Worker → Lago API
                        ↓
                   Customer Mapping
                        ↓
                   PostgreSQL DB
```

## Quick Start

1. **Setup Environment**:
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

2. **Deploy Services**:
   ```bash
   # On Linux/Mac
   ./deploy.sh deploy
   
   # On Windows
   docker-compose up -d
   ```

3. **Verify Integration**:
   ```bash
   ./deploy.sh test
   ```

## Configuration

### Environment Variables

#### Required Variables
- `POSTGRES_PASSWORD`: Database password
- `LITELLM_MASTER_KEY`: LiteLLM master key for authentication
- `LAGO_API_KEY`: Lago API key for billing operations

#### Service URLs
- `LITELLM_API_URL`: LiteLLM API URL (default: http://localhost:4000)
- `LAGO_API_URL`: Lago API URL (default: http://localhost:3000)

#### Processing Configuration
- `MAX_RETRIES`: Maximum retry attempts for failed events (default: 3)
- `RETRY_DELAY`: Delay between retry attempts in seconds (default: 60)
- `BATCH_SIZE`: Number of events to process in each batch (default: 100)
- `WEBHOOK_TIMEOUT`: Timeout for webhook requests in seconds (default: 30)

## Customer Mapping

Before processing events, customers must be mapped between LiteLLM and Lago:

### Create Customer Mapping

```bash
curl -X POST http://localhost:8080/customers/mapping \
  -H "Authorization: Bearer YOUR_LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "litellm_customer_id": "customer-1",
    "lago_customer_id": "lago-customer-1",
    "lago_organization_id": "lago-org-1",
    "billing_plan": "ai_basic",
    "is_active": true
  }'
```

### Get Customer Mapping

```bash
curl -H "Authorization: Bearer YOUR_LITELLM_MASTER_KEY" \
     http://localhost:8080/customers/customer-1/mapping
```

## Webhook Integration

### LiteLLM Configuration

Configure LiteLLM to send webhooks to the integration service:

```yaml
# In LiteLLM config.yaml
litellm_settings:
  success_callback: ["webhook"]
  callbacks:
    - callback_name: "webhook"
      callback_type: "webhook"
      callback_vars:
        webhook_url: "http://integration-service:8080/webhook/litellm/usage"
        webhook_secret: "your_webhook_secret"
```

### Webhook Payload

The service expects LiteLLM usage events in this format:

```json
{
  "id": "request_id",
  "user": "customer_id",
  "model": "gpt-4o-mini",
  "prompt_tokens": 100,
  "completion_tokens": 200,
  "total_tokens": 300,
  "spend": 0.0001,
  "startTime": "2024-01-01T00:00:00Z",
  "endTime": "2024-01-01T00:00:01Z",
  "api_key": "hashed_api_key",
  "request_id": "unique_request_id"
}
```

## Event Processing

### Event Flow

1. **Webhook Reception**: LiteLLM sends usage event to webhook endpoint
2. **Customer Lookup**: Service looks up customer mapping in database
3. **Event Transformation**: Converts LiteLLM event to Lago event format
4. **Queue Storage**: Stores event in database queue for processing
5. **Immediate Processing**: Attempts to send event to Lago immediately
6. **Background Processing**: Worker processes failed/queued events

### Event States

- **pending**: Event queued for processing
- **processing**: Event currently being processed
- **completed**: Event successfully sent to Lago
- **failed**: Event failed after maximum retries

### Retry Logic

- Failed events are automatically retried up to `MAX_RETRIES` times
- Exponential backoff with `RETRY_DELAY` between attempts
- Events exceeding max retries are marked as permanently failed

## Monitoring

### Health Checks

- **Service Health**: `http://localhost:8080/health`
- **Database**: PostgreSQL connection check
- **Lago API**: Lago API connectivity check
- **Redis**: Redis connection check

### Metrics

#### Prometheus Metrics

Available at `http://localhost:9090/metrics`:

- `webhook_requests_total`: Total webhook requests by source and status
- `event_processing_duration_seconds`: Event processing duration histogram
- `lago_api_requests_total`: Total Lago API requests by method and status
- `failed_events_total`: Total failed events by error type
- `active_customers_total`: Current number of active customers
- `pending_events_total`: Current number of pending events

#### Application Metrics

Available at `http://localhost:8080/metrics`:

```json
{
  "total_events": 1000,
  "completed_events": 950,
  "failed_events": 30,
  "pending_events": 20,
  "active_customers": 5
}
```

### Logging

Structured logging with configurable levels:

```bash
# View all logs
./deploy.sh logs

# View specific service logs
./deploy.sh logs integration-service
./deploy.sh logs worker
```

## Database Schema

### Customer Mappings

```sql
CREATE TABLE customer_mappings (
    litellm_customer_id VARCHAR(255) PRIMARY KEY,
    lago_customer_id VARCHAR(255) NOT NULL,
    lago_organization_id VARCHAR(255) NOT NULL,
    billing_plan VARCHAR(100) DEFAULT 'ai_basic',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

### Event Queue

```sql
CREATE TABLE event_queue (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_id VARCHAR(255) NOT NULL,
    external_customer_id VARCHAR(255) NOT NULL,
    event_data JSONB NOT NULL,
    customer_mapping_id VARCHAR(255) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    retry_count INTEGER DEFAULT 0,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    processed_at TIMESTAMP,
    last_retry_at TIMESTAMP
);
```

## API Reference

### Webhook Endpoints

#### POST /webhook/litellm/usage
Receives usage events from LiteLLM.

**Headers:**
- `X-Webhook-Signature`: Optional webhook signature for verification

**Body:** LiteLLM usage event JSON

**Response:**
```json
{
  "status": "accepted",
  "message": "Event queued for processing"
}
```

### Customer Management

#### POST /customers/mapping
Create or update customer mapping.

**Headers:**
- `Authorization: Bearer {LITELLM_MASTER_KEY}`

**Body:**
```json
{
  "litellm_customer_id": "customer-1",
  "lago_customer_id": "lago-customer-1",
  "lago_organization_id": "lago-org-1",
  "billing_plan": "ai_basic",
  "is_active": true
}
```

#### GET /customers/{customer_id}/mapping
Get customer mapping by LiteLLM customer ID.

**Headers:**
- `Authorization: Bearer {LITELLM_MASTER_KEY}`

### Monitoring Endpoints

#### GET /health
Service health check.

#### GET /metrics
Application metrics.

#### GET /metrics/prometheus
Prometheus-formatted metrics.

## Troubleshooting

### Common Issues

1. **Events Not Processing**:
   - Check customer mapping exists
   - Verify Lago API connectivity
   - Check worker service status

2. **Authentication Errors**:
   - Verify LITELLM_MASTER_KEY is correct
   - Check LAGO_API_KEY is valid
   - Ensure webhook signature is correct

3. **Database Connection Issues**:
   - Check PostgreSQL is running
   - Verify database credentials
   - Check network connectivity

4. **High Retry Rates**:
   - Check Lago API status
   - Verify network connectivity
   - Review error logs for patterns

### Debug Commands

```bash
# Check service status
./deploy.sh status

# View logs
./deploy.sh logs integration-service

# Check database
docker-compose exec postgres psql -U integration integration

# Test webhook endpoint
curl -X POST http://localhost:8080/webhook/litellm/usage \
  -H "Content-Type: application/json" \
  -d '{"id":"test","user":"demo-customer-1","model":"gpt-4o-mini",...}'

# Check queue status
docker-compose exec postgres psql -U integration integration \
  -c "SELECT status, COUNT(*) FROM event_queue GROUP BY status;"
```

### Performance Tuning

1. **Database Optimization**:
   - Increase connection pool size for high throughput
   - Add indexes for frequently queried columns
   - Regular cleanup of old completed events

2. **Worker Scaling**:
   - Increase `WORKER_CONCURRENCY` for parallel processing
   - Deploy multiple worker instances
   - Adjust `BATCH_SIZE` based on load

3. **Network Optimization**:
   - Increase `WEBHOOK_TIMEOUT` for slow networks
   - Implement connection pooling
   - Use persistent connections

## Security Considerations

1. **API Keys**: Store securely, rotate regularly
2. **Webhook Signatures**: Enable signature verification
3. **Database**: Use strong passwords, enable SSL
4. **Network**: Use firewalls, VPN for production
5. **Monitoring**: Enable audit logging, set up alerts

## Production Deployment

For production deployment:

1. **External Database**: Use managed PostgreSQL service
2. **Load Balancing**: Deploy multiple service instances
3. **SSL/TLS**: Configure HTTPS with valid certificates
4. **Monitoring**: Set up comprehensive monitoring and alerting
5. **Backup Strategy**: Implement automated backups
6. **Disaster Recovery**: Plan for multi-region deployment

## Support

For issues and questions:

1. Check logs for error messages
2. Review configuration files
3. Test individual components
4. Check network connectivity
5. Verify API keys and credentials