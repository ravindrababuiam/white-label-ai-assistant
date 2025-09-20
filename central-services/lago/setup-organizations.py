#!/usr/bin/env python3
"""
Lago Organization and Customer Setup Script
Creates organizations, customers, and billing plans for the white-label AI platform
"""

import os
import json
import asyncio
import logging
from datetime import datetime
from typing import Dict, Any, List, Optional
import aiohttp
from dataclasses import dataclass

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@dataclass
class CustomerConfig:
    """Customer configuration for onboarding"""
    customer_id: str
    organization_name: str
    aws_account_id: str
    deployment_region: str
    usage_mode: str = "external"
    contact_email: str = ""
    allowed_models: List[str] = None

class LagoAPIClient:
    """Client for interacting with Lago API"""
    
    def __init__(self, api_url: str, api_key: str):
        self.api_url = api_url.rstrip('/')
        self.api_key = api_key
        self.session: Optional[aiohttp.ClientSession] = None
    
    async def __aenter__(self):
        self.session = aiohttp.ClientSession(
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json"
            },
            timeout=aiohttp.ClientTimeout(total=30)
        )
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self.session:
            await self.session.close()
    
    async def create_organization(self, name: str, email: str, webhook_url: str = None) -> Dict[str, Any]:
        """Create a new organization in Lago"""
        payload = {
            "organization": {
                "name": name,
                "email": email,
                "country": "US",
                "default_currency": "EUR",
                "address_line1": "",
                "address_line2": "",
                "state": "",
                "zipcode": "",
                "city": "",
                "timezone": "UTC",
                "webhook_url": webhook_url,
                "vat_rate": 0.0,
                "document_numbering": "per_customer",
                "document_number_prefix": "AI-",
                "net_payment_term": 30
            }
        }
        
        async with self.session.post(f"{self.api_url}/api/v1/organizations", json=payload) as response:
            if response.status == 200:
                result = await response.json()
                logger.info(f"Created organization: {name}")
                return result["organization"]
            else:
                error_text = await response.text()
                logger.error(f"Failed to create organization {name}: {response.status} - {error_text}")
                raise Exception(f"Failed to create organization: {error_text}")
    
    async def create_customer(self, org_id: str, customer_config: CustomerConfig) -> Dict[str, Any]:
        """Create a new customer in Lago"""
        payload = {
            "customer": {
                "external_id": customer_config.customer_id,
                "name": customer_config.organization_name,
                "email": customer_config.contact_email or f"admin@{customer_config.customer_id}.com",
                "country": "US",
                "currency": "EUR",
                "timezone": "UTC",
                "address_line1": "",
                "address_line2": "",
                "state": "",
                "zipcode": "",
                "city": "",
                "metadata": {
                    "aws_account_id": customer_config.aws_account_id,
                    "deployment_region": customer_config.deployment_region,
                    "usage_mode": customer_config.usage_mode,
                    "allowed_models": customer_config.allowed_models or []
                }
            }
        }
        
        async with self.session.post(f"{self.api_url}/api/v1/customers", json=payload) as response:
            if response.status == 200:
                result = await response.json()
                logger.info(f"Created customer: {customer_config.customer_id}")
                return result["customer"]
            else:
                error_text = await response.text()
                logger.error(f"Failed to create customer {customer_config.customer_id}: {response.status} - {error_text}")
                raise Exception(f"Failed to create customer: {error_text}")
    
    async def create_billable_metric(self, name: str, code: str, aggregation_type: str = "sum_agg", field_name: str = None) -> Dict[str, Any]:
        """Create a billable metric in Lago"""
        payload = {
            "billable_metric": {
                "name": name,
                "code": code,
                "description": f"Billable metric for {name}",
                "aggregation_type": aggregation_type,
                "field_name": field_name,
                "group": {}
            }
        }
        
        async with self.session.post(f"{self.api_url}/api/v1/billable_metrics", json=payload) as response:
            if response.status == 200:
                result = await response.json()
                logger.info(f"Created billable metric: {name}")
                return result["billable_metric"]
            else:
                error_text = await response.text()
                logger.error(f"Failed to create billable metric {name}: {response.status} - {error_text}")
                raise Exception(f"Failed to create billable metric: {error_text}")
    
    async def create_plan(self, name: str, code: str, charges: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Create a billing plan in Lago"""
        payload = {
            "plan": {
                "name": name,
                "code": code,
                "description": f"Billing plan for {name}",
                "interval": "monthly",
                "pay_in_advance": False,
                "amount_cents": 0,
                "amount_currency": "EUR",
                "trial_period": 0,
                "charges": charges
            }
        }
        
        async with self.session.post(f"{self.api_url}/api/v1/plans", json=payload) as response:
            if response.status == 200:
                result = await response.json()
                logger.info(f"Created plan: {name}")
                return result["plan"]
            else:
                error_text = await response.text()
                logger.error(f"Failed to create plan {name}: {response.status} - {error_text}")
                raise Exception(f"Failed to create plan: {error_text}")
    
    async def create_subscription(self, customer_external_id: str, plan_code: str) -> Dict[str, Any]:
        """Create a subscription for a customer"""
        payload = {
            "subscription": {
                "external_customer_id": customer_external_id,
                "plan_code": plan_code,
                "name": f"AI Usage Subscription for {customer_external_id}",
                "external_id": f"sub_{customer_external_id}_{int(datetime.now().timestamp())}"
            }
        }
        
        async with self.session.post(f"{self.api_url}/api/v1/subscriptions", json=payload) as response:
            if response.status == 200:
                result = await response.json()
                logger.info(f"Created subscription for customer: {customer_external_id}")
                return result["subscription"]
            else:
                error_text = await response.text()
                logger.error(f"Failed to create subscription for {customer_external_id}: {response.status} - {error_text}")
                raise Exception(f"Failed to create subscription: {error_text}")

class LagoSetupManager:
    """Manages the complete setup of Lago for the white-label AI platform"""
    
    def __init__(self, api_url: str, api_key: str):
        self.api_url = api_url
        self.api_key = api_key
        self.billable_metrics = {}
        self.plans = {}
    
    async def setup_billable_metrics(self, client: LagoAPIClient):
        """Create all required billable metrics"""
        metrics = [
            {
                "name": "AI Input Tokens",
                "code": "ai_input_tokens",
                "aggregation_type": "sum_agg",
                "field_name": "input_tokens"
            },
            {
                "name": "AI Output Tokens", 
                "code": "ai_output_tokens",
                "aggregation_type": "sum_agg",
                "field_name": "output_tokens"
            },
            {
                "name": "AI API Requests",
                "code": "ai_requests",
                "aggregation_type": "count_agg",
                "field_name": None
            },
            {
                "name": "AI Usage Cost",
                "code": "ai_usage_cost",
                "aggregation_type": "sum_agg", 
                "field_name": "cost_usd"
            }
        ]
        
        for metric in metrics:
            try:
                result = await client.create_billable_metric(
                    metric["name"],
                    metric["code"],
                    metric["aggregation_type"],
                    metric["field_name"]
                )
                self.billable_metrics[metric["code"]] = result
            except Exception as e:
                logger.warning(f"Metric {metric['code']} might already exist: {e}")
    
    async def setup_billing_plans(self, client: LagoAPIClient):
        """Create billing plans for different usage tiers"""
        
        # Basic plan - pay per use
        basic_charges = [
            {
                "billable_metric_id": self.billable_metrics["ai_input_tokens"]["lago_id"],
                "charge_model": "standard",
                "pay_in_advance": False,
                "invoiceable": True,
                "properties": {
                    "amount": "0.001"  # €0.001 per 1k input tokens
                }
            },
            {
                "billable_metric_id": self.billable_metrics["ai_output_tokens"]["lago_id"],
                "charge_model": "standard", 
                "pay_in_advance": False,
                "invoiceable": True,
                "properties": {
                    "amount": "0.002"  # €0.002 per 1k output tokens
                }
            }
        ]
        
        # Premium plan - graduated pricing
        premium_charges = [
            {
                "billable_metric_id": self.billable_metrics["ai_input_tokens"]["lago_id"],
                "charge_model": "graduated",
                "pay_in_advance": False,
                "invoiceable": True,
                "properties": {
                    "graduated_ranges": [
                        {
                            "from_value": 0,
                            "to_value": 1000000,
                            "per_unit_amount": "0.001",
                            "flat_amount": "0"
                        },
                        {
                            "from_value": 1000001,
                            "to_value": 10000000,
                            "per_unit_amount": "0.0008",
                            "flat_amount": "0"
                        },
                        {
                            "from_value": 10000001,
                            "to_value": None,
                            "per_unit_amount": "0.0006",
                            "flat_amount": "0"
                        }
                    ]
                }
            },
            {
                "billable_metric_id": self.billable_metrics["ai_output_tokens"]["lago_id"],
                "charge_model": "graduated",
                "pay_in_advance": False,
                "invoiceable": True,
                "properties": {
                    "graduated_ranges": [
                        {
                            "from_value": 0,
                            "to_value": 1000000,
                            "per_unit_amount": "0.002",
                            "flat_amount": "0"
                        },
                        {
                            "from_value": 1000001,
                            "to_value": 10000000,
                            "per_unit_amount": "0.0016",
                            "flat_amount": "0"
                        },
                        {
                            "from_value": 10000001,
                            "to_value": None,
                            "per_unit_amount": "0.0012",
                            "flat_amount": "0"
                        }
                    ]
                }
            }
        ]
        
        plans = [
            {
                "name": "AI Basic Plan",
                "code": "ai_basic",
                "charges": basic_charges
            },
            {
                "name": "AI Premium Plan", 
                "code": "ai_premium",
                "charges": premium_charges
            }
        ]
        
        for plan in plans:
            try:
                result = await client.create_plan(
                    plan["name"],
                    plan["code"],
                    plan["charges"]
                )
                self.plans[plan["code"]] = result
            except Exception as e:
                logger.warning(f"Plan {plan['code']} might already exist: {e}")
    
    async def setup_customer(self, client: LagoAPIClient, org_id: str, customer_config: CustomerConfig, plan_code: str = "ai_basic"):
        """Setup a complete customer with subscription"""
        try:
            # Create customer
            customer = await client.create_customer(org_id, customer_config)
            
            # Create subscription
            subscription = await client.create_subscription(customer_config.customer_id, plan_code)
            
            logger.info(f"Successfully set up customer {customer_config.customer_id} with subscription")
            return {
                "customer": customer,
                "subscription": subscription
            }
        except Exception as e:
            logger.error(f"Failed to setup customer {customer_config.customer_id}: {e}")
            raise

async def main():
    """Main setup function"""
    # Configuration
    api_url = os.getenv("LAGO_API_URL", "http://localhost:3000")
    api_key = os.getenv("LAGO_API_KEY", "")
    
    if not api_key:
        logger.error("LAGO_API_KEY environment variable is required")
        return
    
    # Sample customer configurations
    customers = [
        CustomerConfig(
            customer_id="demo-customer-1",
            organization_name="Demo Organization 1",
            aws_account_id="123456789012",
            deployment_region="eu-west-1",
            usage_mode="external",
            contact_email="admin@demo1.com",
            allowed_models=["gpt-4o-mini", "claude-3-haiku"]
        ),
        CustomerConfig(
            customer_id="demo-customer-2", 
            organization_name="Demo Organization 2",
            aws_account_id="123456789013",
            deployment_region="us-east-1",
            usage_mode="hybrid",
            contact_email="admin@demo2.com",
            allowed_models=["gpt-4o", "claude-3-5-sonnet"]
        )
    ]
    
    setup_manager = LagoSetupManager(api_url, api_key)
    
    async with LagoAPIClient(api_url, api_key) as client:
        try:
            # Setup billable metrics
            logger.info("Setting up billable metrics...")
            await setup_manager.setup_billable_metrics(client)
            
            # Setup billing plans
            logger.info("Setting up billing plans...")
            await setup_manager.setup_billing_plans(client)
            
            # Create organization
            logger.info("Creating organization...")
            organization = await client.create_organization(
                name=os.getenv("DEFAULT_ORGANIZATION_NAME", "White Label AI Platform"),
                email=os.getenv("DEFAULT_ORGANIZATION_EMAIL", "admin@yourcompany.com"),
                webhook_url=os.getenv("LITELLM_WEBHOOK_URL", "http://localhost:8000/webhook/usage")
            )
            
            # Setup customers
            logger.info("Setting up customers...")
            for customer_config in customers:
                await setup_manager.setup_customer(
                    client,
                    organization["lago_id"],
                    customer_config,
                    "ai_basic"
                )
            
            logger.info("Lago setup completed successfully!")
            
            # Print summary
            print("\n" + "="*50)
            print("LAGO SETUP SUMMARY")
            print("="*50)
            print(f"Organization ID: {organization['lago_id']}")
            print(f"API URL: {api_url}")
            print(f"Frontend URL: {os.getenv('LAGO_FRONT_URL', 'http://localhost:8080')}")
            print("\nCustomers created:")
            for customer in customers:
                print(f"  - {customer.customer_id} ({customer.organization_name})")
            print("\nBillable metrics created:")
            for code, metric in setup_manager.billable_metrics.items():
                print(f"  - {code}: {metric['name']}")
            print("\nPlans created:")
            for code, plan in setup_manager.plans.items():
                print(f"  - {code}: {plan['name']}")
            print("="*50)
            
        except Exception as e:
            logger.error(f"Setup failed: {e}")
            raise

if __name__ == "__main__":
    asyncio.run(main())