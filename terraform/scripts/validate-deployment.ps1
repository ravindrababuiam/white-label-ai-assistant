# Validation script for infrastructure foundation deployment
# This script checks if the infrastructure was deployed correctly

param(
    [switch]$Verbose
)

# Function to print colored output
function Write-Status {
    param(
        [string]$Status,
        [string]$Message
    )
    
    switch ($Status) {
        "SUCCESS" { Write-Host "✓ $Message" -ForegroundColor Green }
        "ERROR" { Write-Host "✗ $Message" -ForegroundColor Red }
        "WARNING" { Write-Host "⚠ $Message" -ForegroundColor Yellow }
        "INFO" { Write-Host "ℹ $Message" -ForegroundColor Cyan }
    }
}

# Function to check if command exists
function Test-Command {
    param([string]$Command)
    
    try {
        Get-Command $Command -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

# Check prerequisites
function Test-Prerequisites {
    Write-Status "INFO" "Checking prerequisites..."
    
    if (-not (Test-Command "terraform")) {
        Write-Status "ERROR" "Terraform is not installed"
        exit 1
    }
    
    if (-not (Test-Command "aws")) {
        Write-Status "ERROR" "AWS CLI is not installed"
        exit 1
    }
    
    if (-not (Test-Command "kubectl")) {
        Write-Status "ERROR" "kubectl is not installed"
        exit 1
    }
    
    Write-Status "SUCCESS" "All prerequisites are installed"
}

# Check AWS credentials
function Test-AwsCredentials {
    Write-Status "INFO" "Checking AWS credentials..."
    
    try {
        $identity = aws sts get-caller-identity --output json | ConvertFrom-Json
        
        Write-Status "SUCCESS" "AWS credentials are valid"
        Write-Status "INFO" "Account ID: $($identity.Account)"
        Write-Status "INFO" "User/Role: $($identity.Arn)"
    }
    catch {
        Write-Status "ERROR" "AWS credentials are not configured or invalid"
        exit 1
    }
}

# Check Terraform state
function Test-TerraformState {
    Write-Status "INFO" "Checking Terraform state..."
    
    if (-not (Test-Path "terraform.tfstate") -and -not (Test-Path ".terraform/terraform.tfstate")) {
        Write-Status "ERROR" "No Terraform state file found. Run 'terraform apply' first."
        exit 1
    }
    
    Write-Status "SUCCESS" "Terraform state file found"
}

# Get Terraform outputs
function Get-TerraformOutputs {
    Write-Status "INFO" "Getting Terraform outputs..."
    
    try {
        $script:ClusterName = terraform output -raw cluster_id 2>$null
        $script:ClusterEndpoint = terraform output -raw cluster_endpoint 2>$null
        $script:VpcId = terraform output -raw vpc_id 2>$null
        $script:AwsRegion = terraform output -raw aws_region 2>$null
        
        if (-not $script:AwsRegion) {
            $script:AwsRegion = aws configure get region
        }
        
        if (-not $script:ClusterName) {
            Write-Status "ERROR" "Could not get cluster name from Terraform outputs"
            exit 1
        }
        
        Write-Status "SUCCESS" "Retrieved Terraform outputs"
        Write-Status "INFO" "Cluster Name: $script:ClusterName"
        Write-Status "INFO" "Cluster Endpoint: $script:ClusterEndpoint"
        Write-Status "INFO" "VPC ID: $script:VpcId"
        Write-Status "INFO" "AWS Region: $script:AwsRegion"
    }
    catch {
        Write-Status "ERROR" "Failed to get Terraform outputs: $($_.Exception.Message)"
        exit 1
    }
}

# Check EKS cluster status
function Test-EksCluster {
    Write-Status "INFO" "Checking EKS cluster status..."
    
    try {
        $clusterInfo = aws eks describe-cluster --name $script:ClusterName --region $script:AwsRegion --output json | ConvertFrom-Json
        $clusterStatus = $clusterInfo.cluster.status
        
        if ($clusterStatus -eq "ACTIVE") {
            Write-Status "SUCCESS" "EKS cluster is active"
        }
        else {
            Write-Status "WARNING" "EKS cluster status: $clusterStatus"
        }
    }
    catch {
        Write-Status "ERROR" "EKS cluster not found or error occurred"
        exit 1
    }
}

# Check node groups
function Test-NodeGroups {
    Write-Status "INFO" "Checking EKS node groups..."
    
    try {
        $nodeGroups = aws eks list-nodegroups --cluster-name $script:ClusterName --region $script:AwsRegion --output json | ConvertFrom-Json
        
        if ($nodeGroups.nodegroups.Count -eq 0) {
            Write-Status "ERROR" "No node groups found"
            exit 1
        }
        
        Write-Status "SUCCESS" "Found node groups: $($nodeGroups.nodegroups -join ', ')"
        
        # Check each node group status
        foreach ($ng in $nodeGroups.nodegroups) {
            try {
                $ngInfo = aws eks describe-nodegroup --cluster-name $script:ClusterName --nodegroup-name $ng --region $script:AwsRegion --output json | ConvertFrom-Json
                $ngStatus = $ngInfo.nodegroup.status
                
                if ($ngStatus -eq "ACTIVE") {
                    Write-Status "SUCCESS" "Node group '$ng' is active"
                }
                else {
                    Write-Status "WARNING" "Node group '$ng' status: $ngStatus"
                }
            }
            catch {
                Write-Status "WARNING" "Could not check status of node group '$ng'"
            }
        }
    }
    catch {
        Write-Status "ERROR" "Failed to list node groups"
        exit 1
    }
}

# Check kubectl connectivity
function Test-KubectlConnectivity {
    Write-Status "INFO" "Checking kubectl connectivity..."
    
    try {
        # Update kubeconfig
        aws eks update-kubeconfig --region $script:AwsRegion --name $script:ClusterName | Out-Null
        Write-Status "SUCCESS" "Updated kubeconfig"
        
        # Test kubectl connectivity
        $nodes = kubectl get nodes --no-headers 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Status "SUCCESS" "kubectl can connect to cluster"
            
            $nodeCount = ($nodes | Measure-Object).Count
            Write-Status "INFO" "Number of nodes: $nodeCount"
            
            # Show node status
            foreach ($line in $nodes) {
                $parts = $line -split '\s+'
                $nodeName = $parts[0]
                $nodeStatus = $parts[1]
                
                if ($nodeStatus -eq "Ready") {
                    Write-Status "SUCCESS" "Node '$nodeName' is ready"
                }
                else {
                    Write-Status "WARNING" "Node '$nodeName' status: $nodeStatus"
                }
            }
        }
        else {
            Write-Status "ERROR" "kubectl cannot connect to cluster"
            exit 1
        }
    }
    catch {
        Write-Status "ERROR" "Failed to configure or test kubectl: $($_.Exception.Message)"
        exit 1
    }
}

# Check essential pods
function Test-EssentialPods {
    Write-Status "INFO" "Checking essential system pods..."
    
    try {
        # Check kube-system pods
        $pendingPods = kubectl get pods -n kube-system --field-selector=status.phase=Pending --no-headers 2>$null
        $failedPods = kubectl get pods -n kube-system --field-selector=status.phase=Failed --no-headers 2>$null
        
        $pendingCount = if ($pendingPods) { ($pendingPods | Measure-Object).Count } else { 0 }
        $failedCount = if ($failedPods) { ($failedPods | Measure-Object).Count } else { 0 }
        
        if ($pendingCount -eq 0 -and $failedCount -eq 0) {
            Write-Status "SUCCESS" "All kube-system pods are running"
        }
        else {
            Write-Status "WARNING" "Found $pendingCount pending and $failedCount failed pods in kube-system"
        }
        
        # Check specific essential pods
        $essentialPods = @("coredns", "aws-node", "kube-proxy")
        
        foreach ($podName in $essentialPods) {
            $pods = kubectl get pods -n kube-system -l "k8s-app=$podName" --no-headers 2>$null
            $podCount = if ($pods) { ($pods | Measure-Object).Count } else { 0 }
            
            if ($podCount -gt 0) {
                Write-Status "SUCCESS" "Found $podCount $podName pod(s)"
            }
            else {
                Write-Status "WARNING" "No $podName pods found"
            }
        }
    }
    catch {
        Write-Status "WARNING" "Could not check all pod statuses: $($_.Exception.Message)"
    }
}

# Main validation function
function Main {
    Write-Host "=========================================" -ForegroundColor White
    Write-Host "Infrastructure Foundation Validation" -ForegroundColor White
    Write-Host "=========================================" -ForegroundColor White
    Write-Host
    
    Test-Prerequisites
    Write-Host
    
    Test-AwsCredentials
    Write-Host
    
    Test-TerraformState
    Write-Host
    
    Get-TerraformOutputs
    Write-Host
    
    Test-EksCluster
    Write-Host
    
    Test-NodeGroups
    Write-Host
    
    Test-KubectlConnectivity
    Write-Host
    
    Test-EssentialPods
    Write-Host
    
    Write-Status "SUCCESS" "Infrastructure foundation validation completed!"
    Write-Host
    Write-Status "INFO" "Next steps:"
    Write-Host "  1. Deploy customer stack components (S3, Qdrant, Ollama)" -ForegroundColor Cyan
    Write-Host "  2. Install AWS Load Balancer Controller" -ForegroundColor Cyan
    Write-Host "  3. Deploy Open WebUI application" -ForegroundColor Cyan
    Write-Host "  4. Configure monitoring and logging" -ForegroundColor Cyan
}

# Run main function
Main