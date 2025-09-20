-- Initialize Integration Service database

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- Customer mappings table
CREATE TABLE IF NOT EXISTS customer_mappings (
    litellm_customer_id VARCHAR(255) PRIMARY KEY,
    lago_customer_id VARCHAR(255) NOT NULL,
    lago_organization_id VARCHAR(255) NOT NULL,
    billing_plan VARCHAR(100) DEFAULT 'ai_basic',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_customer_mappings_lago_customer ON customer_mappings (lago_customer_id);
CREATE INDEX IF NOT EXISTS idx_customer_mappings_lago_org ON customer_mappings (lago_organization_id);
CREATE INDEX IF NOT EXISTS idx_customer_mappings_active ON customer_mappings (is_active);

-- Event queue table
CREATE TABLE IF NOT EXISTS event_queue (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_id VARCHAR(255) NOT NULL,
    external_customer_id VARCHAR(255) NOT NULL,
    event_data JSONB NOT NULL,
    customer_mapping_id VARCHAR(255) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    retry_count INTEGER DEFAULT 0,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    processed_at TIMESTAMP,
    last_retry_at TIMESTAMP,
    FOREIGN KEY (customer_mapping_id) REFERENCES customer_mappings(litellm_customer_id)
);

CREATE INDEX IF NOT EXISTS idx_event_queue_status ON event_queue (status);
CREATE INDEX IF NOT EXISTS idx_event_queue_customer ON event_queue (customer_mapping_id);
CREATE INDEX IF NOT EXISTS idx_event_queue_created ON event_queue (created_at);
CREATE INDEX IF NOT EXISTS idx_event_queue_transaction ON event_queue (transaction_id);
CREATE INDEX IF NOT EXISTS idx_event_queue_retry ON event_queue (status, retry_count, last_retry_at);

-- Event processing statistics table
CREATE TABLE IF NOT EXISTS processing_stats (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    date DATE NOT NULL,
    customer_mapping_id VARCHAR(255),
    total_events INTEGER DEFAULT 0,
    successful_events INTEGER DEFAULT 0,
    failed_events INTEGER DEFAULT 0,
    total_input_tokens BIGINT DEFAULT 0,
    total_output_tokens BIGINT DEFAULT 0,
    total_cost_usd DECIMAL(15,5) DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW(),
    FOREIGN KEY (customer_mapping_id) REFERENCES customer_mappings(litellm_customer_id),
    UNIQUE(date, customer_mapping_id)
);

CREATE INDEX IF NOT EXISTS idx_processing_stats_date ON processing_stats (date);
CREATE INDEX IF NOT EXISTS idx_processing_stats_customer ON processing_stats (customer_mapping_id);

-- Error log table
CREATE TABLE IF NOT EXISTS error_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    error_type VARCHAR(100) NOT NULL,
    error_message TEXT NOT NULL,
    event_id UUID,
    customer_mapping_id VARCHAR(255),
    context JSONB,
    created_at TIMESTAMP DEFAULT NOW(),
    FOREIGN KEY (event_id) REFERENCES event_queue(id),
    FOREIGN KEY (customer_mapping_id) REFERENCES customer_mappings(litellm_customer_id)
);

CREATE INDEX IF NOT EXISTS idx_error_logs_type ON error_logs (error_type);
CREATE INDEX IF NOT EXISTS idx_error_logs_created ON error_logs (created_at);
CREATE INDEX IF NOT EXISTS idx_error_logs_customer ON error_logs (customer_mapping_id);

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for customer_mappings
CREATE TRIGGER update_customer_mappings_updated_at
    BEFORE UPDATE ON customer_mappings
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Function to log errors
CREATE OR REPLACE FUNCTION log_error(
    p_error_type VARCHAR(100),
    p_error_message TEXT,
    p_event_id UUID DEFAULT NULL,
    p_customer_mapping_id VARCHAR(255) DEFAULT NULL,
    p_context JSONB DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    error_id UUID;
BEGIN
    INSERT INTO error_logs (error_type, error_message, event_id, customer_mapping_id, context)
    VALUES (p_error_type, p_error_message, p_event_id, p_customer_mapping_id, p_context)
    RETURNING id INTO error_id;
    
    RETURN error_id;
END;
$$ LANGUAGE plpgsql;

-- Function to update daily statistics
CREATE OR REPLACE FUNCTION update_daily_stats(
    p_date DATE,
    p_customer_mapping_id VARCHAR(255),
    p_events INTEGER DEFAULT 1,
    p_successful INTEGER DEFAULT 0,
    p_failed INTEGER DEFAULT 0,
    p_input_tokens BIGINT DEFAULT 0,
    p_output_tokens BIGINT DEFAULT 0,
    p_cost_usd DECIMAL(15,5) DEFAULT 0
)
RETURNS VOID AS $$
BEGIN
    INSERT INTO processing_stats (
        date, customer_mapping_id, total_events, successful_events, failed_events,
        total_input_tokens, total_output_tokens, total_cost_usd
    )
    VALUES (
        p_date, p_customer_mapping_id, p_events, p_successful, p_failed,
        p_input_tokens, p_output_tokens, p_cost_usd
    )
    ON CONFLICT (date, customer_mapping_id) DO UPDATE SET
        total_events = processing_stats.total_events + p_events,
        successful_events = processing_stats.successful_events + p_successful,
        failed_events = processing_stats.failed_events + p_failed,
        total_input_tokens = processing_stats.total_input_tokens + p_input_tokens,
        total_output_tokens = processing_stats.total_output_tokens + p_output_tokens,
        total_cost_usd = processing_stats.total_cost_usd + p_cost_usd;
END;
$$ LANGUAGE plpgsql;

-- Function to get customer statistics
CREATE OR REPLACE FUNCTION get_customer_stats(
    p_customer_id VARCHAR(255),
    p_start_date DATE DEFAULT CURRENT_DATE - INTERVAL '30 days',
    p_end_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    total_events BIGINT,
    successful_events BIGINT,
    failed_events BIGINT,
    total_input_tokens BIGINT,
    total_output_tokens BIGINT,
    total_cost_usd DECIMAL(15,5),
    success_rate DECIMAL(5,2),
    daily_breakdown JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COALESCE(SUM(ps.total_events), 0)::BIGINT as total_events,
        COALESCE(SUM(ps.successful_events), 0)::BIGINT as successful_events,
        COALESCE(SUM(ps.failed_events), 0)::BIGINT as failed_events,
        COALESCE(SUM(ps.total_input_tokens), 0)::BIGINT as total_input_tokens,
        COALESCE(SUM(ps.total_output_tokens), 0)::BIGINT as total_output_tokens,
        COALESCE(SUM(ps.total_cost_usd), 0)::DECIMAL(15,5) as total_cost_usd,
        CASE 
            WHEN SUM(ps.total_events) > 0 
            THEN ROUND((SUM(ps.successful_events)::DECIMAL / SUM(ps.total_events)) * 100, 2)
            ELSE 0
        END as success_rate,
        COALESCE(
            jsonb_object_agg(
                ps.date,
                jsonb_build_object(
                    'events', ps.total_events,
                    'successful', ps.successful_events,
                    'failed', ps.failed_events,
                    'input_tokens', ps.total_input_tokens,
                    'output_tokens', ps.total_output_tokens,
                    'cost_usd', ps.total_cost_usd
                )
            ),
            '{}'::jsonb
        ) as daily_breakdown
    FROM processing_stats ps
    WHERE ps.customer_mapping_id = p_customer_id
    AND ps.date >= p_start_date
    AND ps.date <= p_end_date;
END;
$$ LANGUAGE plpgsql;

-- Function to clean old data
CREATE OR REPLACE FUNCTION cleanup_old_data(
    p_retention_days INTEGER DEFAULT 90
)
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    -- Delete old completed events
    DELETE FROM event_queue 
    WHERE status = 'completed' 
    AND processed_at < NOW() - INTERVAL '1 day' * p_retention_days;
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    
    -- Delete old error logs
    DELETE FROM error_logs 
    WHERE created_at < NOW() - INTERVAL '1 day' * p_retention_days;
    
    -- Keep processing stats longer (1 year)
    DELETE FROM processing_stats 
    WHERE created_at < NOW() - INTERVAL '365 days';
    
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Create view for monitoring dashboard
CREATE OR REPLACE VIEW monitoring_dashboard AS
SELECT 
    cm.litellm_customer_id,
    cm.lago_customer_id,
    cm.lago_organization_id,
    cm.billing_plan,
    cm.is_active,
    COALESCE(eq_stats.pending_events, 0) as pending_events,
    COALESCE(eq_stats.failed_events, 0) as failed_events,
    COALESCE(ps_today.total_events, 0) as events_today,
    COALESCE(ps_today.successful_events, 0) as successful_events_today,
    COALESCE(ps_today.total_cost_usd, 0) as cost_today,
    COALESCE(ps_month.total_events, 0) as events_this_month,
    COALESCE(ps_month.total_cost_usd, 0) as cost_this_month,
    cm.created_at as customer_created_at,
    cm.updated_at as customer_updated_at
FROM customer_mappings cm
LEFT JOIN (
    SELECT 
        customer_mapping_id,
        COUNT(*) FILTER (WHERE status = 'pending') as pending_events,
        COUNT(*) FILTER (WHERE status = 'failed') as failed_events
    FROM event_queue 
    GROUP BY customer_mapping_id
) eq_stats ON cm.litellm_customer_id = eq_stats.customer_mapping_id
LEFT JOIN processing_stats ps_today ON (
    cm.litellm_customer_id = ps_today.customer_mapping_id 
    AND ps_today.date = CURRENT_DATE
)
LEFT JOIN (
    SELECT 
        customer_mapping_id,
        SUM(total_events) as total_events,
        SUM(total_cost_usd) as total_cost_usd
    FROM processing_stats 
    WHERE date >= DATE_TRUNC('month', CURRENT_DATE)
    GROUP BY customer_mapping_id
) ps_month ON cm.litellm_customer_id = ps_month.customer_mapping_id;

-- Insert sample customer mappings for testing
INSERT INTO customer_mappings (
    litellm_customer_id, 
    lago_customer_id, 
    lago_organization_id, 
    billing_plan
) VALUES 
('demo-customer-1', 'lago-customer-1', 'lago-org-1', 'ai_basic'),
('demo-customer-2', 'lago-customer-2', 'lago-org-1', 'ai_premium')
ON CONFLICT (litellm_customer_id) DO NOTHING;

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_event_queue_composite ON event_queue (status, created_at, retry_count);
CREATE INDEX IF NOT EXISTS idx_processing_stats_composite ON processing_stats (customer_mapping_id, date);

-- Grant necessary permissions (adjust as needed for your setup)
-- GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO integration_user;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO integration_user;