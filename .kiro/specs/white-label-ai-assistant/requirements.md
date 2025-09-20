# Requirements Document

## Introduction

This project involves building a white-label intranet AI assistant platform for businesses that supports both local GDPR-compliant deployment and external API routing. The solution uses a hybrid architecture where customer-specific components (Open WebUI, Ollama, storage) are deployed in individual AWS subaccounts, while shared services (LiteLLM Proxy, Lago billing) run centrally. The system must be easily clonable for new customers and include MCP server integration for task execution and external tool connectivity.

## Requirements

### Requirement 1: Customer Stack Deployment

**User Story:** As a business customer, I want my AI assistant to run entirely within my own AWS environment, so that my data remains GDPR-compliant and never leaves my control.

#### Acceptance Criteria

1. WHEN a new customer is onboarded THEN the system SHALL deploy Open WebUI and Ollama in the customer's AWS subaccount using ECS or EKS
2. WHEN the customer stack is provisioned THEN the system SHALL create dedicated S3 buckets for document storage within the customer's subaccount
3. WHEN the customer stack is deployed THEN the system SHALL provision Qdrant vector database for embeddings storage within the customer's subaccount
4. WHEN employees upload documents to Open WebUI THEN the system SHALL store files in the customer's S3 bucket and upsert embeddings into their Qdrant instance
5. WHEN processing customer data THEN the system SHALL ensure all data processing occurs within the customer's AWS subaccount boundaries
6. WHEN the customer stack is configured THEN the system SHALL implement network isolation to prevent data leakage outside the subaccount

### Requirement 2: Central Shared Services

**User Story:** As the service provider, I want to manage billing and API routing centrally across all customers, so that I can efficiently operate the platform without duplicating infrastructure.

#### Acceptance Criteria

1. WHEN the central stack is deployed THEN the system SHALL provision LiteLLM Proxy for usage tracking, quotas, and model routing
2. WHEN the central stack is deployed THEN the system SHALL provision self-hosted Lago for usage-based billing
3. WHEN API calls are made THEN LiteLLM SHALL track usage events and forward them to Lago for billing calculation
4. WHEN calculating billing THEN the system SHALL charge based on tokens consumed (€/1k tokens)
5. WHEN a new customer is added THEN the system SHALL only require creating organizations and users in Lago and adding keys/accounts in LiteLLM
6. WHEN customers access billing information THEN they SHALL log directly into Lago's multi-tenant dashboard to view usage and invoices

### Requirement 3: Dual Usage Mode Support

**User Story:** As a business user, I want to choose between local-only AI processing or external API access based on my company's data policies, so that I can balance security requirements with AI capabilities.

#### Acceptance Criteria

1. WHEN using local mode THEN the system SHALL route all AI requests to the customer's Ollama instance
2. WHEN using external mode THEN the system SHALL route requests through LiteLLM to approved external APIs (OpenAI, Anthropic, etc.)
3. WHEN company policy is configured THEN the system SHALL enforce routing rules based on customer preferences
4. WHEN switching between modes THEN the system SHALL maintain consistent user experience in Open WebUI
5. WHEN using external APIs THEN the system SHALL apply proper authentication and quota management through LiteLLM

### Requirement 4: MCP Server Integration

**User Story:** As a business user, I want my AI assistant to execute tasks and connect to external tools through MCP servers, so that the assistant can perform actions beyond just conversation.

#### Acceptance Criteria

1. WHEN Open WebUI is deployed THEN the system SHALL enable MCP integration capabilities
2. WHEN the system is initially configured THEN it SHALL connect to the agency's existing MCP server as a test case
3. WHEN new MCP servers are added THEN the system SHALL support easy configuration and connection
4. WHEN MCP servers are integrated THEN they SHALL be accessible through the Open WebUI interface
5. WHEN designing MCP integration THEN the system SHALL be future-proof for adding multiple MCP servers per customer

### Requirement 5: Clonability and Automation

**User Story:** As the service provider, I want to automatically replicate the customer stack for new clients, so that onboarding is fast and consistent without manual deployment steps.

#### Acceptance Criteria

1. WHEN creating deployment automation THEN the system SHALL provide Terraform configurations for infrastructure provisioning
2. WHEN creating deployment automation THEN the system SHALL provide Helm charts or Docker configurations for application deployment
3. WHEN deploying to a new AWS subaccount THEN the automation SHALL replicate Open WebUI, Ollama, S3, and Qdrant consistently
4. WHEN running automation THEN it SHALL require minimal manual configuration or intervention
5. WHEN automation completes THEN the new customer environment SHALL be fully functional and ready for use
6. WHEN automation fails THEN it SHALL provide clear error messages and rollback capabilities

### Requirement 6: Documentation and Knowledge Transfer

**User Story:** As the service provider's team, I want comprehensive documentation and training, so that I can operate, maintain, and scale the platform effectively.

#### Acceptance Criteria

1. WHEN documentation is delivered THEN it SHALL include complete setup instructions for both customer and central stacks
2. WHEN documentation is delivered THEN it SHALL include customer onboarding procedures and workflows
3. WHEN documentation is delivered THEN it SHALL include upgrade procedures for all components
4. WHEN documentation is delivered THEN it SHALL include backup and disaster recovery procedures
5. WHEN documentation is delivered THEN it SHALL include scaling guidelines for growing usage
6. WHEN knowledge transfer occurs THEN it SHALL include a live session with the service provider's team
7. WHEN documentation is created THEN it SHALL be maintained in a format that supports ongoing updates

### Requirement 7: Production Readiness and Monitoring

**User Story:** As the service provider, I want the system to be production-ready with proper monitoring and alerting, so that I can ensure reliable service for all customers.

#### Acceptance Criteria

1. WHEN the system is deployed THEN it SHALL include health checks for all critical components
2. WHEN system issues occur THEN the system SHALL provide alerting and monitoring capabilities
3. WHEN deployed to production THEN the system SHALL implement proper security configurations and access controls
4. WHEN handling customer data THEN the system SHALL implement appropriate encryption at rest and in transit
5. WHEN scaling is needed THEN the system SHALL support horizontal scaling of customer stacks
6. WHEN maintenance is required THEN the system SHALL support rolling updates with minimal downtime