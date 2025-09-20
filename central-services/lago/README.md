# Lago Billing System Deployment

This directory contains the complete deployment configuration for Lago billing system with PostgreSQL backend, Redis caching, and integrated API management service for customer and organization management.

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Lago API      │    │  API Integration│    │   PostgreSQL    │
│   :3000         │◄──►│  Service        │◄──►│   Database      │
│                 │    │  :3002          │    │   :5433         │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │              ┌─────────────────┐              │
         └─────────────►│     Redis       │◄─────────────┘
                        │     Cache       │
                        │     :6380       │
                        └─────────────────┘
                                 │
                        ┌─────────────────┐
                        │  Lago Frontend  │
                        │     :8080       │
                        └─────────────────┘
```

## Features

- **Multi-Tenant Billing**: Support for multiple organizations and customers
- **Usage-Based Pricing**: Flexible pricing models with tiered rates
- **Real-Time Usage Tracking**: Integration with LiteLLM for AI usage events
- **Invoice Management**: Automated invoice generation and management
- **Webhook Integration**: Real-time event notifications
- **API Management**: RESTful APIs for customer and billing operations
- **Dashboard**: Web-based dashboard for billing management

## Quick Start

1. **Clone and Configure**
   ```bash
   cd central-services/lago
   cp .env.example .env
   # Edit .env with your configuration
   ```

2. **Generate Encryption Keys**
   ```bash
   # Generate secure keys for .env file
   echo "SECRET_KEY_BASE=$(openssl rand -hex 64)"
   echo "ENCRYPTION_PRIMARY_KEY=$(openssl rand -hex 32)"
   echo "ENCRYPTION_DETERMINISTIC_KEY=$(openssl rand -hex 32)"
   echo "ENCRYPTION_KEY_DERIVATION_SALT=$(openssl rand -hex 32)"
   ```

3. **Deploy Services**
   ```bash
   chmod +x deploy.sh
   ./deploy.sh
   ```

4. **Verify Deployment**
   ```bash
   curl http://localhost:3000/health
   curl http://localhost:3002/health
   curl http://localhost:8080
   ```

## Configuration

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `POSTGRES_PASSWORD` | PostgreSQL database password | Yes |
| `SECRET_KEY_BASE` | Rails secret key (64+ chars) | Yes |
| `ENCRYPTION_PRIMARY_KEY` | Primary encryption key (32 chars) | Yes |
| `ENCRYPTION_DETERMINISTIC_KEY` | Deterministic encryption key (32 chars) | Yes |
| `ENCRYPTION_KEY_DERIVATION_SALT` | Key derivation salt (32 chars) | Yes |
| `LAGO_API_URL` | Lago API URL | Optional |
| `LAGO_FRONT_URL` | Lago Frontend URL | Optional |
| `LAGO_WEBHOOK_SECRET` | Webhook secret key | Optional |
| `LAGO_LICENSE` | Lago license key | Optional |
| `LAGO_SMTP_ADDRESS` | SMTP server address | Optional |
| `LAGO_SMTP_USERNAME` | SMTP username | Optional |
| `LAGO_SMTP_PASSWORD` | SMTP password | Optional |

### Initial Setup

After deployment, the system automatically creates:

- Default billable metric for AI usage (`ai_usage`)
- Default pricing plan for AI services (`ai_usage_plan`)
- Database tables for usage tracking and webhook logs

## API Usage

### Authentication

All API requests require authentication. Use the Lago API key in the Authorization header:

```bash
curl -H "Authorization: Bearer your-lago-api-key" \
     http://localhost:3002/api/customers
```

### Customer Management

Create a new customer:

```bash
curl -X POST http://localhost:3002/api/customers \
  -H "Authorization: Bearer your-lago-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "external_id": "customer-123",
    "name": "Acme Corporation",
    "email": "billing@acme.com",
    "plan_code": "ai_usage_plan"
  }'
```

Get customer details:

```bash
curl http://localhost:3002/api/customers/customer-123 \
  -H "Authorization: Bearer your-lago-api-key"
```

### Usage Tracking

Send usage events via webhook:

```bash
curl -X POST http://localhost:3002/webhooks/litellm \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "usage",
    "timestamp": 1703123456,
    "customer_id": "customer-123",
    "model": "gpt-4o",
    "provider": "openai",
    "tokens_input": 100,
    "tokens_output": 150,
    "total_tokens": 250,
    "cost_usd": 0.00375,
    "request_id": "req-abc123",
    "api_key_hash": "key_a1b2c3"
  }'
```

### Billing Management

Create a billing plan:

```bash
curl -X POST http://localhost:3002/api/billing/plans \
  -H "Authorization: Bearer your-lago-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Premium AI Plan",
    "code": "premium_ai_plan",
    "interval": "monthly",
    "amount_cents": 2000,
    "amount_currency": "USD",
    "charges": [{
      "billable_metric_id": "ai_usage_metric_id",
      "charge_model": "standard",
      "properties": {
        "amount": "0.002"
      }
    }]
  }'
```

Get customer invoices:

```bash
curl http://localhost:3002/api/customers/customer-123/invoices \
  -H "Authorization: Bearer your-lago-api-key"
```

## Webhook Integration

### LiteLLM Integration

The system receives usage events from LiteLLM via webhooks:

- **Endpoint**: `POST /webhooks/litellm`
- **Batch Endpoint**: `POST /webhooks/litellm/batch`
- **Retry Endpoint**: `POST /webhooks/retry`

### Event Processing

Usage events are:

1. Received via webhook
2. Stored in local database
3. Forwarded to Lago for billing
4. Marked as processed

### Webhook Statistics

Get processing statistics:

```bash
curl http://localhost:3002/webhooks/stats
```

## Monitoring

### Health Checks

- **Lago API**: `GET /health`
- **API Integration**: `GET /health`
- **Frontend**: `GET /` (returns 200)
- **Readiness**: `GET /health/ready`
- **Liveness**: `GET /health/live`
- **Metrics**: `GET /health/metrics`

### Logs

View service logs:

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f lago-api
docker-compose logs -f lago-api-integration
```

### Database Access

Connect to PostgreSQL:

```bash
docker-compose exec postgres psql -U lago -d lago
```

Useful queries:

```sql
-- Customer usage statistics
SELECT * FROM aggregate_customer_usage('customer-123', NOW() - INTERVAL '30 days', NOW());

-- Recent usage events
SELECT * FROM litellm_usage_events 
WHERE customer_external_id = 'customer-123' 
ORDER BY timestamp DESC LIMIT 10;

-- Webhook delivery status
SELECT 
  event_type,
  COUNT(*) as total_attempts,
  COUNT(CASE WHEN http_status BETWEEN 200 AND 299 THEN 1 END) as successful,
  COUNT(CASE WHEN http_status >= 400 THEN 1 END) as failed
FROM webhook_delivery_logs
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY event_type;

-- Unprocessed events
SELECT COUNT(*) FROM litellm_usage_events WHERE processed_at IS NULL;
```

### Rails Console

Access Lago Rails console:

```bash
docker-compose exec lago-api bundle exec rails console
```

## Scaling

### Horizontal Scaling

Scale worker processes:

```bash
docker-compose up -d --scale lago-worker=3
```

### Performance Tuning

1. **Database Optimization**
   - Increase PostgreSQL `shared_buffers`
   - Add indexes for frequent queries
   - Enable connection pooling

2. **Redis Optimization**
   - Increase memory allocation
   - Configure persistence settings
   - Enable clustering for high availability

3. **Application Optimization**
   - Adjust worker concurrency
   - Configure connection pools
   - Enable response caching

## Troubleshooting

### Common Issues

1. **Service Won't Start**
   ```bash
   # Check logs
   docker-compose logs lago-api
   
   # Verify environment variables
   docker-compose config
   ```

2. **Database Connection Issues**
   ```bash
   # Test database connectivity
   docker-compose exec postgres pg_isready -U lago
   
   # Check database logs
   docker-compose logs postgres
   ```

3. **Migration Failures**
   ```bash
   # Run migrations manually
   docker-compose exec lago-api bundle exec rails db:migrate
   
   # Reset database (development only)
   docker-compose exec lago-api bundle exec rails db:drop db:create db:migrate
   ```

4. **Webhook Processing Issues**
   ```bash
   # Check API integration logs
   docker-compose logs lago-api-integration
   
   # Retry failed events
   curl -X POST http://localhost:3002/webhooks/retry
   
   # Check webhook stats
   curl http://localhost:3002/webhooks/stats
   ```

### Recovery Procedures

1. **Database Recovery**
   ```bash
   # Backup database
   docker-compose exec postgres pg_dump -U lago lago > backup.sql
   
   # Restore database
   docker-compose exec -T postgres psql -U lago lago < backup.sql
   ```

2. **Service Recovery**
   ```bash
   # Restart all services
   docker-compose restart
   
   # Rebuild and restart
   docker-compose down
   docker-compose up -d --build
   ```

## Security

### Best Practices

1. **Encryption Keys**
   - Use strong, randomly generated keys
   - Rotate keys regularly
   - Store keys securely

2. **Database Security**
   - Use strong passwords
   - Enable SSL connections
   - Regular security updates

3. **API Security**
   - Use HTTPS in production
   - Implement rate limiting
   - Monitor for suspicious activity

4. **Webhook Security**
   - Validate webhook signatures
   - Use HTTPS endpoints
   - Implement retry logic

## Production Deployment

For production deployment:

1. **Use External Services**
   - Managed PostgreSQL (RDS)
   - Managed Redis (ElastiCache)
   - Load balancer (ALB/NLB)

2. **Security Hardening**
   - Enable HTTPS/TLS
   - Configure WAF
   - Implement secrets management

3. **Monitoring & Alerting**
   - CloudWatch/Prometheus
   - Error tracking (Sentry)
   - Performance monitoring

4. **Backup & Recovery**
   - Automated database backups
   - Cross-region replication
   - Disaster recovery procedures

## Integration with LiteLLM

To integrate with LiteLLM, configure the webhook URL in LiteLLM:

```yaml
# In LiteLLM config.yaml
litellm_settings:
  success_callback: ["lago"]
  callback_vars:
    lago_webhook_url: "http://lago-api-integration:3002/webhooks/litellm"
```

This enables automatic usage tracking and billing for AI services.