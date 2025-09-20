#!/bin/bash

# Validation script for infrastructure foundation deployment
# This script checks if the infrastructure was deployed correctly

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    
    case $status in
        "SUCCESS")
            echo -e "${GREEN}✓${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}✗${NC} $message"
            ;;
        "WARNING")
            echo -e "${YELLOW}⚠${NC} $message"
            ;;
        "INFO")
            echo -e "${YELLOW}ℹ${NC} $message"
            ;;
    esac
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    print_status "INFO" "Checking prerequisites..."
    
    if ! command_exists terraform; then
        print_status "ERROR" "Terraform is not installed"
        exit 1
    fi
    
    if ! command_exists aws; then
        print_status "ERROR" "AWS CLI is not installed"
        exit 1
    fi
    
    if ! command_exists kubectl; then
        print_status "ERROR" "kubectl is not installed"
        exit 1
    fi
    
    print_status "SUCCESS" "All prerequisites are installed"
}

# Check AWS credentials
check_aws_credentials() {
    print_status "INFO" "Checking AWS credentials..."
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_status "ERROR" "AWS credentials are not configured or invalid"
        exit 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local user_arn=$(aws sts get-caller-identity --query Arn --output text)
    
    print_status "SUCCESS" "AWS credentials are valid"
    print_status "INFO" "Account ID: $account_id"
    print_status "INFO" "User/Role: $user_arn"
}

# Check Terraform state
check_terraform_state() {
    print_status "INFO" "Checking Terraform state..."
    
    if [ ! -f "terraform.tfstate" ] && [ ! -f ".terraform/terraform.tfstate" ]; then
        print_status "ERROR" "No Terraform state file found. Run 'terraform apply' first."
        exit 1
    fi
    
    print_status "SUCCESS" "Terraform state file found"
}

# Get Terraform outputs
get_terraform_outputs() {
    print_status "INFO" "Getting Terraform outputs..."
    
    CLUSTER_NAME=$(terraform output -raw cluster_id 2>/dev/null || echo "")
    CLUSTER_ENDPOINT=$(terraform output -raw cluster_endpoint 2>/dev/null || echo "")
    VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")
    
    if [ -z "$CLUSTER_NAME" ]; then
        print_status "ERROR" "Could not get cluster name from Terraform outputs"
        exit 1
    fi
    
    print_status "SUCCESS" "Retrieved Terraform outputs"
    print_status "INFO" "Cluster Name: $CLUSTER_NAME"
    print_status "INFO" "Cluster Endpoint: $CLUSTER_ENDPOINT"
    print_status "INFO" "VPC ID: $VPC_ID"
}

# Check EKS cluster status
check_eks_cluster() {
    print_status "INFO" "Checking EKS cluster status..."
    
    local region=$(terraform output -raw aws_region 2>/dev/null || aws configure get region)
    
    if [ -z "$region" ]; then
        print_status "ERROR" "Could not determine AWS region"
        exit 1
    fi
    
    local cluster_status=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$region" --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$cluster_status" = "ACTIVE" ]; then
        print_status "SUCCESS" "EKS cluster is active"
    elif [ "$cluster_status" = "NOT_FOUND" ]; then
        print_status "ERROR" "EKS cluster not found"
        exit 1
    else
        print_status "WARNING" "EKS cluster status: $cluster_status"
    fi
}

# Check node groups
check_node_groups() {
    print_status "INFO" "Checking EKS node groups..."
    
    local region=$(terraform output -raw aws_region 2>/dev/null || aws configure get region)
    local node_groups=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --region "$region" --query 'nodegroups' --output text 2>/dev/null || echo "")
    
    if [ -z "$node_groups" ]; then
        print_status "ERROR" "No node groups found"
        exit 1
    fi
    
    print_status "SUCCESS" "Found node groups: $node_groups"
    
    # Check each node group status
    for ng in $node_groups; do
        local ng_status=$(aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ng" --region "$region" --query 'nodegroup.status' --output text 2>/dev/null || echo "UNKNOWN")
        
        if [ "$ng_status" = "ACTIVE" ]; then
            print_status "SUCCESS" "Node group '$ng' is active"
        else
            print_status "WARNING" "Node group '$ng' status: $ng_status"
        fi
    done
}

# Check kubectl connectivity
check_kubectl_connectivity() {
    print_status "INFO" "Checking kubectl connectivity..."
    
    local region=$(terraform output -raw aws_region 2>/dev/null || aws configure get region)
    
    # Update kubeconfig
    if aws eks update-kubeconfig --region "$region" --name "$CLUSTER_NAME" >/dev/null 2>&1; then
        print_status "SUCCESS" "Updated kubeconfig"
    else
        print_status "ERROR" "Failed to update kubeconfig"
        exit 1
    fi
    
    # Test kubectl connectivity
    if kubectl get nodes >/dev/null 2>&1; then
        print_status "SUCCESS" "kubectl can connect to cluster"
        
        local node_count=$(kubectl get nodes --no-headers | wc -l)
        print_status "INFO" "Number of nodes: $node_count"
        
        # Show node status
        kubectl get nodes --no-headers | while read line; do
            local node_name=$(echo $line | awk '{print $1}')
            local node_status=$(echo $line | awk '{print $2}')
            
            if [ "$node_status" = "Ready" ]; then
                print_status "SUCCESS" "Node '$node_name' is ready"
            else
                print_status "WARNING" "Node '$node_name' status: $node_status"
            fi
        done
    else
        print_status "ERROR" "kubectl cannot connect to cluster"
        exit 1
    fi
}

# Check essential pods
check_essential_pods() {
    print_status "INFO" "Checking essential system pods..."
    
    # Check kube-system pods
    local pending_pods=$(kubectl get pods -n kube-system --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l)
    local failed_pods=$(kubectl get pods -n kube-system --field-selector=status.phase=Failed --no-headers 2>/dev/null | wc -l)
    
    if [ "$pending_pods" -eq 0 ] && [ "$failed_pods" -eq 0 ]; then
        print_status "SUCCESS" "All kube-system pods are running"
    else
        print_status "WARNING" "Found $pending_pods pending and $failed_pods failed pods in kube-system"
    fi
    
    # Check specific essential pods
    local essential_pods=("coredns" "aws-node" "kube-proxy")
    
    for pod_name in "${essential_pods[@]}"; do
        local pod_count=$(kubectl get pods -n kube-system -l k8s-app="$pod_name" --no-headers 2>/dev/null | wc -l)
        
        if [ "$pod_count" -gt 0 ]; then
            print_status "SUCCESS" "Found $pod_count $pod_name pod(s)"
        else
            print_status "WARNING" "No $pod_name pods found"
        fi
    done
}

# Main validation function
main() {
    echo "========================================="
    echo "Infrastructure Foundation Validation"
    echo "========================================="
    echo
    
    check_prerequisites
    echo
    
    check_aws_credentials
    echo
    
    check_terraform_state
    echo
    
    get_terraform_outputs
    echo
    
    check_eks_cluster
    echo
    
    check_node_groups
    echo
    
    check_kubectl_connectivity
    echo
    
    check_essential_pods
    echo
    
    print_status "SUCCESS" "Infrastructure foundation validation completed!"
    echo
    print_status "INFO" "Next steps:"
    echo "  1. Deploy customer stack components (S3, Qdrant, Ollama)"
    echo "  2. Install AWS Load Balancer Controller"
    echo "  3. Deploy Open WebUI application"
    echo "  4. Configure monitoring and logging"
}

# Run main function
main "$@"