-- Initialize LiteLLM database with required extensions and initial data

-- Create extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- Create custom indexes for performance
CREATE INDEX IF NOT EXISTS idx_litellm_spendlogs_starttime ON "LiteLLM_SpendLogs" ("startTime");
CREATE INDEX IF NOT EXISTS idx_litellm_spendlogs_end_user ON "LiteLLM_SpendLogs" ("end_user");
CREATE INDEX IF NOT EXISTS idx_litellm_spendlogs_model ON "LiteLLM_SpendLogs" ("model");
CREATE INDEX IF NOT EXISTS idx_litellm_spendlogs_api_key ON "LiteLLM_SpendLogs" ("api_key");

-- Create custom function for usage aggregation
CREATE OR REPLACE FUNCTION get_usage_by_customer(
    customer_id TEXT,
    start_date TIMESTAMP DEFAULT NOW() - INTERVAL '30 days',
    end_date TIMESTAMP DEFAULT NOW()
)
RETURNS TABLE (
    total_requests BIGINT,
    total_tokens_input BIGINT,
    total_tokens_output BIGINT,
    total_cost DECIMAL,
    model_breakdown JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(*)::BIGINT as total_requests,
        COALESCE(SUM("prompt_tokens"), 0)::BIGINT as total_tokens_input,
        COALESCE(SUM("completion_tokens"), 0)::BIGINT as total_tokens_output,
        COALESCE(SUM("spend"), 0)::DECIMAL as total_cost,
        COALESCE(
            jsonb_object_agg(
                "model", 
                jsonb_build_object(
                    'requests', COUNT(*),
                    'input_tokens', COALESCE(SUM("prompt_tokens"), 0),
                    'output_tokens', COALESCE(SUM("completion_tokens"), 0),
                    'cost', COALESCE(SUM("spend"), 0)
                )
            ), 
            '{}'::jsonb
        ) as model_breakdown
    FROM "LiteLLM_SpendLogs"
    WHERE "end_user" = customer_id
    AND "startTime" >= start_date
    AND "startTime" <= end_date
    GROUP BY "model";
END;
$$ LANGUAGE plpgsql;

-- Create function for webhook payload generation
CREATE OR REPLACE FUNCTION generate_lago_webhook_payload(
    spend_log_id UUID
)
RETURNS JSONB AS $$
DECLARE
    log_record RECORD;
    payload JSONB;
BEGIN
    SELECT * INTO log_record
    FROM "LiteLLM_SpendLogs"
    WHERE "request_id" = spend_log_id::TEXT;
    
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;
    
    payload := jsonb_build_object(
        'event_type', 'usage',
        'timestamp', EXTRACT(EPOCH FROM log_record."startTime"),
        'customer_id', log_record."end_user",
        'model', log_record."model",
        'provider', COALESCE(log_record."custom_llm_provider", 'unknown'),
        'tokens_input', COALESCE(log_record."prompt_tokens", 0),
        'tokens_output', COALESCE(log_record."completion_tokens", 0),
        'total_tokens', COALESCE(log_record."total_tokens", 0),
        'cost_usd', COALESCE(log_record."spend", 0),
        'request_id', log_record."request_id",
        'api_key_hash', log_record."api_key",
        'metadata', jsonb_build_object(
            'user_id', log_record."user",
            'team_id', log_record."team_id",
            'request_tags', log_record."request_tags"
        )
    );
    
    RETURN payload;
END;
$$ LANGUAGE plpgsql;

-- Create trigger function for real-time webhook notifications
CREATE OR REPLACE FUNCTION notify_usage_event()
RETURNS TRIGGER AS $$
BEGIN
    -- Notify application about new usage event for webhook processing
    PERFORM pg_notify('usage_event', NEW."request_id");
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for usage notifications
DROP TRIGGER IF EXISTS usage_event_trigger ON "LiteLLM_SpendLogs";
CREATE TRIGGER usage_event_trigger
    AFTER INSERT ON "LiteLLM_SpendLogs"
    FOR EACH ROW
    EXECUTE FUNCTION notify_usage_event();

-- Insert default admin user (will be created by LiteLLM on first run)
-- This is just for reference, actual user creation happens through LiteLLM API

COMMENT ON FUNCTION get_usage_by_customer IS 'Aggregates usage statistics for a specific customer within a date range';
COMMENT ON FUNCTION generate_lago_webhook_payload IS 'Generates standardized webhook payload for Lago billing integration';
COMMENT ON FUNCTION notify_usage_event IS 'Triggers real-time notifications for new usage events';