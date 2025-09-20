-- Initialize Lago database with required extensions and custom functions

-- Create extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Create custom indexes for performance (will be created after Lago migrations)
-- These are additional indexes for our specific use cases

-- Function to generate API keys for organizations
CREATE OR REPLACE FUNCTION generate_organization_api_key()
RETURNS TEXT AS $$
BEGIN
    RETURN 'lago_' || encode(gen_random_bytes(32), 'hex');
END;
$$ LANGUAGE plpgsql;

-- Function to calculate usage-based charges
CREATE OR REPLACE FUNCTION calculate_usage_charge(
    base_rate DECIMAL,
    usage_amount DECIMAL,
    tier_rates JSONB DEFAULT NULL
)
RETURNS DECIMAL AS $$
DECLARE
    total_charge DECIMAL := 0;
    tier JSONB;
    tier_limit DECIMAL;
    tier_rate DECIMAL;
    remaining_usage DECIMAL := usage_amount;
BEGIN
    -- Simple flat rate if no tiers
    IF tier_rates IS NULL OR jsonb_array_length(tier_rates) = 0 THEN
        RETURN base_rate * usage_amount;
    END IF;
    
    -- Tiered pricing calculation
    FOR tier IN SELECT * FROM jsonb_array_elements(tier_rates)
    LOOP
        tier_limit := (tier->>'limit')::DECIMAL;
        tier_rate := (tier->>'rate')::DECIMAL;
        
        IF remaining_usage <= 0 THEN
            EXIT;
        END IF;
        
        IF tier_limit IS NULL OR remaining_usage <= tier_limit THEN
            -- Last tier or usage fits in current tier
            total_charge := total_charge + (remaining_usage * tier_rate);
            remaining_usage := 0;
        ELSE
            -- Usage exceeds current tier limit
            total_charge := total_charge + (tier_limit * tier_rate);
            remaining_usage := remaining_usage - tier_limit;
        END IF;
    END LOOP;
    
    -- If there's remaining usage and no more tiers, use base rate
    IF remaining_usage > 0 THEN
        total_charge := total_charge + (remaining_usage * base_rate);
    END IF;
    
    RETURN total_charge;
END;
$$ LANGUAGE plpgsql;

-- Function to aggregate usage events by customer and time period
CREATE OR REPLACE FUNCTION aggregate_customer_usage(
    customer_external_id TEXT,
    start_date TIMESTAMP,
    end_date TIMESTAMP
)
RETURNS TABLE (
    model TEXT,
    total_requests BIGINT,
    total_input_tokens BIGINT,
    total_output_tokens BIGINT,
    total_tokens BIGINT,
    total_cost_usd DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        (properties->>'model')::TEXT as model,
        COUNT(*)::BIGINT as total_requests,
        COALESCE(SUM((properties->>'tokens_input')::BIGINT), 0)::BIGINT as total_input_tokens,
        COALESCE(SUM((properties->>'tokens_output')::BIGINT), 0)::BIGINT as total_output_tokens,
        COALESCE(SUM((properties->>'total_tokens')::BIGINT), 0)::BIGINT as total_tokens,
        COALESCE(SUM((properties->>'cost_usd')::DECIMAL), 0)::DECIMAL as total_cost_usd
    FROM events e
    JOIN customers c ON e.customer_id = c.id
    WHERE c.external_id = customer_external_id
    AND e.timestamp >= start_date
    AND e.timestamp <= end_date
    AND e.code = 'ai_usage'
    GROUP BY (properties->>'model');
END;
$$ LANGUAGE plpgsql;

-- Function to create webhook payload for external systems
CREATE OR REPLACE FUNCTION create_webhook_payload(
    event_type TEXT,
    organization_external_id TEXT,
    customer_external_id TEXT,
    invoice_data JSONB
)
RETURNS JSONB AS $$
DECLARE
    payload JSONB;
BEGIN
    payload := jsonb_build_object(
        'event_type', event_type,
        'timestamp', EXTRACT(EPOCH FROM NOW()),
        'organization_id', organization_external_id,
        'customer_id', customer_external_id,
        'data', invoice_data
    );
    
    RETURN payload;
END;
$$ LANGUAGE plpgsql;

-- Create custom tables for LiteLLM integration
CREATE TABLE IF NOT EXISTS litellm_usage_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    request_id VARCHAR(255) UNIQUE NOT NULL,
    customer_external_id VARCHAR(255) NOT NULL,
    model VARCHAR(100) NOT NULL,
    provider VARCHAR(50) NOT NULL,
    tokens_input INTEGER DEFAULT 0,
    tokens_output INTEGER DEFAULT 0,
    total_tokens INTEGER DEFAULT 0,
    cost_usd DECIMAL(10,6) DEFAULT 0,
    timestamp TIMESTAMP DEFAULT NOW(),
    processed_at TIMESTAMP,
    lago_event_id UUID,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_litellm_usage_events_customer ON litellm_usage_events(customer_external_id);
CREATE INDEX IF NOT EXISTS idx_litellm_usage_events_timestamp ON litellm_usage_events(timestamp);
CREATE INDEX IF NOT EXISTS idx_litellm_usage_events_model ON litellm_usage_events(model);
CREATE INDEX IF NOT EXISTS idx_litellm_usage_events_processed ON litellm_usage_events(processed_at);

-- Create webhook logs table
CREATE TABLE IF NOT EXISTS webhook_delivery_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    webhook_endpoint_id UUID,
    event_type VARCHAR(100) NOT NULL,
    payload JSONB NOT NULL,
    http_status INTEGER,
    response_body TEXT,
    delivered_at TIMESTAMP,
    retry_count INTEGER DEFAULT 0,
    next_retry_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_webhook_delivery_logs_endpoint ON webhook_delivery_logs(webhook_endpoint_id);
CREATE INDEX IF NOT EXISTS idx_webhook_delivery_logs_delivered ON webhook_delivery_logs(delivered_at);
CREATE INDEX IF NOT EXISTS idx_webhook_delivery_logs_retry ON webhook_delivery_logs(next_retry_at);

-- Function to update timestamps
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for updating updated_at column
CREATE TRIGGER update_litellm_usage_events_updated_at
    BEFORE UPDATE ON litellm_usage_events
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Comments for documentation
COMMENT ON TABLE litellm_usage_events IS 'Stores usage events from LiteLLM for billing integration';
COMMENT ON TABLE webhook_delivery_logs IS 'Logs webhook delivery attempts and responses';
COMMENT ON FUNCTION generate_organization_api_key IS 'Generates secure API keys for organizations';
COMMENT ON FUNCTION calculate_usage_charge IS 'Calculates charges based on usage and tiered pricing';
COMMENT ON FUNCTION aggregate_customer_usage IS 'Aggregates usage statistics for a customer within a time period';