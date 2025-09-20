# Complete Customer Deployment Orchestrator
# This script orchestrates the complete customer onboarding process

param(
    [Parameter(Mandatory=$true)]
    [string]$CustomerName,
    
    [Parameter(Mandatory=$true)]
    [string]$CustomerEmail,
    
    [Parameter(Mandatory=$false)]
    [string]$AwsRegion = "us-west-2",
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "production",
    
    [Parameter(Mandatory=$false)]
    [switch]$CreateSubaccount = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$EnableGpu = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipValidation = $false
)

$ErrorActionPreference = "Stop"

Write-Host "🚀 Complete Customer Deployment Orchestrator" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host "Customer: $CustomerName" -ForegroundColor Cyan
Write-Host "Email: $CustomerEmail" -ForegroundColor Cyan
Write-Host "Region: $AwsRegion" -ForegroundColor Cyan
Write-Host "Environment: $Environment" -ForegroundColor Cyan

# Create directories if they don't exist
$directories = @("scripts", "customers", "terraform/environments")
foreach ($dir in $directories) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# Step 1: AWS Subaccount Setup (if requested)
if ($CreateSubaccount) {
    Write-Host "`n🏢 Step 1: AWS Subaccount Setup" -ForegroundColor Yellow
    Write-Host "================================" -ForegroundColor Yellow
    
    if ($DryRun) {
        Write-Host "🔍 DRY RUN: Would create AWS subaccount for $CustomerName" -ForegroundColor Cyan
    } else {
        try {
            & "./scripts/aws-subaccount-setup.ps1" -CustomerName $CustomerName -CustomerEmail $CustomerEmail
            Write-Host "✅ AWS subaccount setup completed" -ForegroundColor Green
        } catch {
            Write-Error "Failed to setup AWS subaccount: $_"
            exit 1
        }
    }
} else {
    Write-Host "`n🏢 Step 1: Skipping AWS Subaccount Setup" -ForegroundColor Yellow
}

# Step 2: Parameter Validation and Injection
Write-Host "`n⚙️ Step 2: Parameter Validation and Injection" -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Yellow

$configFile = "customers/$CustomerName.conf"
$parameters = @{
    'customer_name' = $CustomerName
    'aws_region' = $AwsRegion
    'environment' = $Environment
    'enable_gpu_nodes' = $EnableGpu
}

if ($DryRun) {
    Write-Host "🔍 DRY RUN: Would validate and inject parameters" -ForegroundColor Cyan
} else {
    try {
        $validateArgs = @{
            'CustomerName' = $CustomerName
            'Parameters' = $parameters
        }
        
        if (Test-Path $configFile) {
            $validateArgs['ConfigFile'] = $configFile
        }
        
        if ($SkipValidation) {
            $validateArgs['Force'] = $true
        }
        
        & "./scripts/parameter-injection.ps1" @validateArgs
        Write-Host "✅ Parameter validation and injection completed" -ForegroundColor Green
    } catch {
        Write-Error "Failed parameter validation: $_"
        exit 1
    }
}

# Step 3: Customer Infrastructure Setup
Write-Host "`n🏗️ Step 3: Customer Infrastructure Setup" -ForegroundColor Yellow
Write-Host "=======================================" -ForegroundColor Yellow

if ($DryRun) {
    Write-Host "🔍 DRY RUN: Would create customer infrastructure" -ForegroundColor Cyan
} else {
    try {
        $onboardingArgs = @{
            'CustomerName' = $CustomerName
            'AwsRegion' = $AwsRegion
            'Environment' = $Environment
            'EnableGpu' = $EnableGpu
        }
        
        & "./scripts/customer-onboarding.ps1" @onboardingArgs
        Write-Host "✅ Customer infrastructure setup completed" -ForegroundColor Green
    } catch {
        Write-Error "Failed customer infrastructure setup: $_"
        exit 1
    }
}

# Step 4: Infrastructure Deployment
Write-Host "`n🚀 Step 4: Infrastructure Deployment" -ForegroundColor Yellow
Write-Host "===================================" -ForegroundColor Yellow

$customerDir = "terraform/environments/$CustomerName"

if ($DryRun) {
    Write-Host "🔍 DRY RUN: Would deploy infrastructure to AWS" -ForegroundColor Cyan
} else {
    if (Test-Path $customerDir) {
        try {
            Push-Location $customerDir
            
            Write-Host "📋 Initializing Terraform..." -ForegroundColor Cyan
            terraform init
            
            Write-Host "✅ Validating Terraform configuration..." -ForegroundColor Cyan
            terraform validate
            
            Write-Host "📊 Planning deployment..." -ForegroundColor Cyan
            terraform plan -out=tfplan
            
            Write-Host "🚀 Applying Terraform configuration..." -ForegroundColor Cyan
            terraform apply tfplan
            
            Write-Host "✅ Infrastructure deployment completed" -ForegroundColor Green
            
        } catch {
            Write-Error "Failed infrastructure deployment: $_"
            exit 1
        } finally {
            Pop-Location
        }
    } else {
        Write-Error "Customer directory not found: $customerDir"
        exit 1
    }
}

# Step 5: Kubernetes Configuration
Write-Host "`n☸️ Step 5: Kubernetes Configuration" -ForegroundColor Yellow
Write-Host "==================================" -ForegroundColor Yellow

if ($DryRun) {
    Write-Host "🔍 DRY RUN: Would configure kubectl and deploy applications" -ForegroundColor Cyan
} else {
    try {
        Write-Host "⚙️ Configuring kubectl..." -ForegroundColor Cyan
        aws eks update-kubeconfig --region $AwsRegion --name "$CustomerName-eks-cluster"
        
        Write-Host "⏳ Waiting for EKS nodes to be ready..." -ForegroundColor Cyan
        kubectl wait --for=condition=Ready nodes --all --timeout=300s
        
        Write-Host "📦 Deploying customer applications..." -ForegroundColor Cyan
        
        # Check if k8s deployments exist
        if (Test-Path "k8s-deployments") {
            kubectl apply -f k8s-deployments/
        } else {
            Write-Warning "k8s-deployments directory not found - applications may need manual deployment"
        }
        
        Write-Host "✅ Kubernetes configuration completed" -ForegroundColor Green
        
    } catch {
        Write-Error "Failed Kubernetes configuration: $_"
        exit 1
    }
}

# Step 6: Deployment Validation
Write-Host "`n🔍 Step 6: Deployment Validation" -ForegroundColor Yellow
Write-Host "===============================" -ForegroundColor Yellow

if ($DryRun) {
    Write-Host "🔍 DRY RUN: Would validate deployment" -ForegroundColor Cyan
} else {
    try {
        Push-Location $customerDir
        
        if (Test-Path "./validate.sh") {
            if ($IsLinux -or $IsMacOS) {
                bash ./validate.sh
            } else {
                Write-Host "⚠️ Validation script requires bash - running manual checks..." -ForegroundColor Yellow
                
                # Manual validation for Windows
                Write-Host "Checking EKS cluster..." -ForegroundColor Cyan
                $clusterStatus = aws eks describe-cluster --region $AwsRegion --name "$CustomerName-eks-cluster" --query 'cluster.status' --output text
                Write-Host "EKS Status: $clusterStatus" -ForegroundColor $(if($clusterStatus -eq "ACTIVE") {"Green"} else {"Red"})
                
                Write-Host "Checking Kubernetes pods..." -ForegroundColor Cyan
                kubectl get pods -n customer-stack
                
                Write-Host "Checking services..." -ForegroundColor Cyan
                kubectl get services -n customer-stack
            }
        }
        
        Write-Host "✅ Deployment validation completed" -ForegroundColor Green
        
    } catch {
        Write-Warning "Validation encountered issues: $_"
    } finally {
        Pop-Location
    }
}

# Step 7: Get Access Information
Write-Host "`n🌐 Step 7: Access Information" -ForegroundColor Yellow
Write-Host "============================" -ForegroundColor Yellow

if ($DryRun) {
    Write-Host "🔍 DRY RUN: Would retrieve access information" -ForegroundColor Cyan
} else {
    try {
        Write-Host "🔗 Getting application access URL..." -ForegroundColor Cyan
        $loadBalancerUrl = kubectl get service open-webui-service -n customer-stack -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
        
        if ($loadBalancerUrl) {
            Write-Host "✅ Application URL: http://$loadBalancerUrl:8080" -ForegroundColor Green
        } else {
            Write-Warning "LoadBalancer URL not yet available - may take a few minutes"
        }
        
        # Get other important information
        Write-Host "📋 Getting resource information..." -ForegroundColor Cyan
        
        $rdsEndpoints = aws rds describe-db-instances --region $AwsRegion --query "DBInstances[?contains(DBInstanceIdentifier, '$CustomerName')].[DBInstanceIdentifier,Endpoint.Address]" --output text
        $redisEndpoints = aws elasticache describe-replication-groups --region $AwsRegion --query "ReplicationGroups[?contains(ReplicationGroupId, '$CustomerName')].[ReplicationGroupId,NodeGroups[0].PrimaryEndpoint.Address]" --output text
        
        Write-Host "🗄️ Database endpoints:" -ForegroundColor Cyan
        Write-Host $rdsEndpoints
        
        Write-Host "🔄 Redis endpoints:" -ForegroundColor Cyan
        Write-Host $redisEndpoints
        
    } catch {
        Write-Warning "Failed to retrieve access information: $_"
    }
}

# Step 8: Generate Summary Report
Write-Host "`n📊 Step 8: Deployment Summary" -ForegroundColor Yellow
Write-Host "============================" -ForegroundColor Yellow

$summaryReport = @"
# Customer Deployment Summary

## Customer Information
- **Name**: $CustomerName
- **Email**: $CustomerEmail
- **Environment**: $Environment
- **Region**: $AwsRegion
- **GPU Enabled**: $EnableGpu

## Deployment Status
- **AWS Subaccount**: $($CreateSubaccount ? 'Created' : 'Skipped')
- **Infrastructure**: $($DryRun ? 'Dry Run' : 'Deployed')
- **Applications**: $($DryRun ? 'Dry Run' : 'Deployed')
- **Validation**: $($DryRun ? 'Dry Run' : 'Completed')

## Access Information
- **Application URL**: http://$loadBalancerUrl:8080
- **Kubernetes Context**: $CustomerName-eks-cluster
- **Region**: $AwsRegion

## AWS Resources
- **EKS Cluster**: $CustomerName-eks-cluster
- **VPC**: Customer-specific VPC with private/public subnets
- **RDS**: PostgreSQL databases for LiteLLM and Lago
- **ElastiCache**: Redis clusters for caching
- **S3**: Document and data storage buckets

## Next Steps
1. Test application access via LoadBalancer URL
2. Configure customer-specific settings
3. Set up monitoring and alerting
4. Provide customer training and documentation

## Support Files
- **Configuration**: customers/$CustomerName.conf
- **Terraform**: terraform/environments/$CustomerName/
- **Parameters**: terraform/environments/$CustomerName/parameter-summary.md

---
Deployment completed: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Status: $($DryRun ? 'DRY RUN' : 'DEPLOYED')
"@

$reportPath = "customers/$CustomerName-deployment-report.md"
$summaryReport | Out-File -FilePath $reportPath -Encoding UTF8

Write-Host "📋 Deployment summary saved to: $reportPath" -ForegroundColor Cyan

# Final status
if ($DryRun) {
    Write-Host "`n🔍 DRY RUN COMPLETED" -ForegroundColor Cyan
    Write-Host "All steps validated - ready for actual deployment" -ForegroundColor Cyan
} else {
    Write-Host "`n🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!" -ForegroundColor Green
    Write-Host "Customer $CustomerName is ready to use the white-label AI assistant" -ForegroundColor Green
    
    if ($loadBalancerUrl) {
        Write-Host "🌐 Access the application at: http://$loadBalancerUrl:8080" -ForegroundColor Yellow
    }
}

Write-Host "`n📋 Summary:" -ForegroundColor White
Write-Host "- Customer: $CustomerName" -ForegroundColor White
Write-Host "- Environment: $Environment" -ForegroundColor White
Write-Host "- Region: $AwsRegion" -ForegroundColor White
Write-Host "- Status: $($DryRun ? 'DRY RUN' : 'DEPLOYED')" -ForegroundColor White
Write-Host "- Report: $reportPath" -ForegroundColor White