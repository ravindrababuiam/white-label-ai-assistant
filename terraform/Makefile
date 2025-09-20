# Makefile for White Label AI Assistant Infrastructure

# Default values
CUSTOMER_NAME ?= example-customer
AWS_REGION ?= us-west-2
ENVIRONMENT ?= prod

# Terraform directory
TF_DIR = environments/customer-template

.PHONY: help init plan apply destroy validate clean fmt check

# Default target
help: ## Show this help message
	@echo "White Label AI Assistant - Infrastructure Foundation"
	@echo ""
	@echo "Usage: make [target] [CUSTOMER_NAME=name] [AWS_REGION=region] [ENVIRONMENT=env]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'
	@echo ""
	@echo "Examples:"
	@echo "  make init CUSTOMER_NAME=acme-corp"
	@echo "  make plan CUSTOMER_NAME=acme-corp AWS_REGION=us-east-1"
	@echo "  make apply CUSTOMER_NAME=acme-corp"

init: ## Initialize Terraform
	@echo "Initializing Terraform for customer: $(CUSTOMER_NAME)"
	cd $(TF_DIR) && terraform init

plan: ## Plan Terraform deployment
	@echo "Planning Terraform deployment for customer: $(CUSTOMER_NAME)"
	cd $(TF_DIR) && terraform plan \
		-var="customer_name=$(CUSTOMER_NAME)" \
		-var="aws_region=$(AWS_REGION)" \
		-var="environment=$(ENVIRONMENT)"

apply: ## Apply Terraform configuration
	@echo "Applying Terraform configuration for customer: $(CUSTOMER_NAME)"
	cd $(TF_DIR) && terraform apply \
		-var="customer_name=$(CUSTOMER_NAME)" \
		-var="aws_region=$(AWS_REGION)" \
		-var="environment=$(ENVIRONMENT)"

destroy: ## Destroy Terraform infrastructure
	@echo "Destroying Terraform infrastructure for customer: $(CUSTOMER_NAME)"
	@echo "WARNING: This will permanently delete all resources!"
	@read -p "Are you sure? Type 'yes' to continue: " confirm && [ "$$confirm" = "yes" ]
	cd $(TF_DIR) && terraform destroy \
		-var="customer_name=$(CUSTOMER_NAME)" \
		-var="aws_region=$(AWS_REGION)" \
		-var="environment=$(ENVIRONMENT)"

validate: ## Validate the deployed infrastructure
	@echo "Validating infrastructure for customer: $(CUSTOMER_NAME)"
	cd $(TF_DIR) && powershell -ExecutionPolicy Bypass -File ../../scripts/validate-deployment.ps1

fmt: ## Format Terraform files
	@echo "Formatting Terraform files..."
	terraform fmt -recursive .

check: ## Check Terraform configuration
	@echo "Checking Terraform configuration..."
	cd $(TF_DIR) && terraform validate
	cd $(TF_DIR) && terraform fmt -check -recursive ../../modules/

clean: ## Clean Terraform temporary files
	@echo "Cleaning Terraform temporary files..."
	find . -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	find . -name "*.tfplan" -delete 2>/dev/null || true
	find . -name ".terraform.lock.hcl" -delete 2>/dev/null || true

setup-customer: ## Set up configuration for a new customer
	@echo "Setting up configuration for customer: $(CUSTOMER_NAME)"
	@if [ ! -f "$(TF_DIR)/terraform.tfvars" ]; then \
		cp $(TF_DIR)/terraform.tfvars.example $(TF_DIR)/terraform.tfvars; \
		echo "Created terraform.tfvars from example"; \
		echo "Please edit $(TF_DIR)/terraform.tfvars with customer-specific values"; \
	else \
		echo "terraform.tfvars already exists"; \
	fi

setup-gpu-customer: ## Set up configuration for a GPU-enabled customer
	@echo "Setting up GPU configuration for customer: $(CUSTOMER_NAME)"
	@if [ ! -f "$(TF_DIR)/terraform.tfvars" ]; then \
		cp $(TF_DIR)/terraform-gpu.tfvars.example $(TF_DIR)/terraform.tfvars; \
		echo "Created terraform.tfvars from GPU example"; \
		echo "Please edit $(TF_DIR)/terraform.tfvars with customer-specific values"; \
	else \
		echo "terraform.tfvars already exists"; \
	fi

outputs: ## Show Terraform outputs
	@echo "Terraform outputs for customer: $(CUSTOMER_NAME)"
	cd $(TF_DIR) && terraform output

kubeconfig: ## Update kubectl configuration
	@echo "Updating kubectl configuration for customer: $(CUSTOMER_NAME)"
	@CLUSTER_NAME=$$(cd $(TF_DIR) && terraform output -raw cluster_id 2>/dev/null); \
	REGION=$$(cd $(TF_DIR) && terraform output -raw aws_region 2>/dev/null || echo $(AWS_REGION)); \
	if [ -n "$$CLUSTER_NAME" ]; then \
		aws eks update-kubeconfig --region $$REGION --name $$CLUSTER_NAME; \
		echo "kubectl configured for cluster: $$CLUSTER_NAME"; \
	else \
		echo "Error: Could not get cluster name from Terraform outputs"; \
		exit 1; \
	fi

status: ## Show infrastructure status
	@echo "Infrastructure status for customer: $(CUSTOMER_NAME)"
	@CLUSTER_NAME=$$(cd $(TF_DIR) && terraform output -raw cluster_id 2>/dev/null); \
	REGION=$$(cd $(TF_DIR) && terraform output -raw aws_region 2>/dev/null || echo $(AWS_REGION)); \
	if [ -n "$$CLUSTER_NAME" ]; then \
		echo "Cluster: $$CLUSTER_NAME"; \
		echo "Region: $$REGION"; \
		aws eks describe-cluster --name $$CLUSTER_NAME --region $$REGION --query 'cluster.status' --output text; \
		kubectl get nodes 2>/dev/null || echo "kubectl not configured or cluster not accessible"; \
	else \
		echo "No cluster found or Terraform not applied"; \
	fi