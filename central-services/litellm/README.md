# LiteLLM Proxy Deployment

This directory contains the complete deployment configuration for LiteLLM Proxy with PostgreSQL backend, Redis caching, and integrated webhook service for Lago billing integration.

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   LiteLLM       │    │  Webhook        │    │   PostgreSQL    │
│   Proxy         │◄──►│  Service        │◄──►│   Database      │
│   :4000         │    │  :3001          │    │   :5432         │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │              ┌─────────────────┐              │
         └─────────────►│     Redis       │◄─────────────┘
                        │     Cache       │
                        │     :6379       │
                        └─────────────────┘
```

## Features

- **Multi-Provider Support**: OpenAI, Anthropic, Cohere, Azure OpenAI
- **Usage Tracking**: Comprehensive logging and analytics
- **Rate Limiting**: Per-key quotas and rate limits
- **Caching**: Redis-based response caching
- **Webhook Integration**: Real-time usage events to Lago billing
- **High Availability**: Health checks and auto-restart
- **Security**: API key management and access controls

## Quick Start

1. **Clone and Configure**
   ```bash
   cd central-services/litellm
   cp .env.example .env
   # Edit .env with your configuration
   ```

2. **Deploy Services**
   ```bash
   chmod +x deploy.sh
   ./deploy.sh
   ```

3. **Verify Deployment**
   ```bash
   curl http://localhost:4000/health
   curl http://localhost:3001/health
   ```

## Configuration

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `POSTGRES_PASSWORD` | PostgreSQL database password | Yes |
| `LITELLM_MASTER_KEY` | Master API key for LiteLLM | Yes |
| `LITELLM_SALT_KEY` | Salt key for encryption | Yes |
| `UI_USERNAME` | Web UI username | Yes |
| `UI_PASSWORD` | Web UI password | Yes |
| `OPENAI_API_KEY` | OpenAI API key | Optional |
| `ANTHROPIC_API_KEY` | Anthropic API key | Optional |
| `COHERE_API_KEY` | Cohere API key | Optional |
| `LAGO_WEBHOOK_URL` | Lago webhook endpoint | Optional |
| `LAGO_API_KEY` | Lago API key | Optional |

### Model Configuration

Edit `config.yaml` to add or modify supported models:

```yaml
model_list:
  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: os.environ/OPENAI_API_KEY
    model_info:
      mode: chat
      input_cost_per_token: 0.000005
      output_cost_per_token: 0.000015
```

## API Usage

### Authentication

All requests require the master key in the Authorization header:

```bash
curl -H "Authorization: Bearer sk-your-master-key" \
     http://localhost:4000/v1/chat/completions
```

### Chat Completions

```bash
curl -X POST http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-your-master-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o",
    "messages": [
      {"role": "user", "content": "Hello, world!"}
    ],
    "user": "customer-123"
  }'
```

### Key Management

Create a new API key:

```bash
curl -X POST http://localhost:4000/key/generate \
  -H "Authorization: Bearer sk-your-master-key" \
  -H "Content-Type: application/json" \
  -d '{
    "models": ["gpt-4o", "claude-3-5-sonnet"],
    "max_budget": 100.0,
    "user_id": "customer-123",
    "team_id": "team-456"
  }'
```

## Webhook Integration

The webhook service automatically processes usage events and forwards them to Lago:

### Usage Event Format

```json
{
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
  "api_key_hash": "key_a1b2c3",
  "metadata": {
    "user_id": "user-789",
    "team_id": "team-456"
  }
}
```

### Webhook Endpoints

- `POST /webhooks/usage` - Single usage event
- `POST /webhooks/usage/batch` - Batch usage events
- `POST /webhooks/reprocess` - Reprocess failed events
- `GET /webhooks/stats` - Processing statistics
- `GET /webhooks/validate` - Validate Lago connection

## Monitoring

### Health Checks

- **LiteLLM**: `GET /health`
- **Webhook Service**: `GET /health`
- **Readiness**: `GET /health/ready`
- **Liveness**: `GET /health/live`
- **Metrics**: `GET /health/metrics`

### Logs

View service logs:

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f litellm
docker-compose logs -f webhook-service
```

### Database Queries

Connect to PostgreSQL:

```bash
docker-compose exec postgres psql -U litellm -d litellm
```

Useful queries:

```sql
-- Recent usage statistics
SELECT 
  model,
  COUNT(*) as requests,
  SUM(prompt_tokens) as input_tokens,
  SUM(completion_tokens) as output_tokens,
  SUM(spend) as total_cost
FROM "LiteLLM_SpendLogs"
WHERE "startTime" > NOW() - INTERVAL '24 hours'
GROUP BY model;

-- Customer usage
SELECT * FROM get_usage_by_customer('customer-123', NOW() - INTERVAL '30 days', NOW());

-- Webhook processing status
SELECT 
  success,
  COUNT(*) as count
FROM webhook_logs
WHERE sent_at > NOW() - INTERVAL '1 hour'
GROUP BY success;
```

## Scaling

### Horizontal Scaling

Scale LiteLLM instances:

```bash
docker-compose up -d --scale litellm=3
```

Add load balancer configuration for multiple instances.

### Performance Tuning

1. **Database Optimization**
   - Increase PostgreSQL `shared_buffers`
   - Add indexes for frequent queries
   - Enable connection pooling

2. **Redis Optimization**
   - Increase memory allocation
   - Configure persistence settings
   - Enable clustering for high availability

3. **LiteLLM Optimization**
   - Adjust `num_workers` in config
   - Configure connection pools
   - Enable response caching

## Troubleshooting

### Common Issues

1. **Service Won't Start**
   ```bash
   # Check logs
   docker-compose logs litellm
   
   # Verify environment variables
   docker-compose config
   ```

2. **Database Connection Issues**
   ```bash
   # Test database connectivity
   docker-compose exec postgres pg_isready -U litellm
   
   # Check database logs
   docker-compose logs postgres
   ```

3. **Webhook Failures**
   ```bash
   # Check webhook service logs
   docker-compose logs webhook-service
   
   # Test Lago connectivity
   curl http://localhost:3001/webhooks/validate
   
   # Reprocess failed events
   curl -X POST http://localhost:3001/webhooks/reprocess
   ```

4. **High Memory Usage**
   ```bash
   # Monitor resource usage
   docker stats
   
   # Check Redis memory usage
   docker-compose exec redis redis-cli info memory
   ```

### Recovery Procedures

1. **Database Recovery**
   ```bash
   # Backup database
   docker-compose exec postgres pg_dump -U litellm litellm > backup.sql
   
   # Restore database
   docker-compose exec -T postgres psql -U litellm litellm < backup.sql
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

1. **API Key Management**
   - Rotate master keys regularly
   - Use unique keys per customer
   - Implement key expiration

2. **Network Security**
   - Use HTTPS in production
   - Implement IP whitelisting
   - Configure firewall rules

3. **Database Security**
   - Use strong passwords
   - Enable SSL connections
   - Regular security updates

4. **Monitoring**
   - Enable audit logging
   - Monitor for suspicious activity
   - Set up alerting for failures

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