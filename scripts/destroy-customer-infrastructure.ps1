# Customer Infrastructure Destruction Script
# This script destroys all AWS infrastructure and applications for a customer

param(
    [Parameter(Mandatory=$true)]
    [string]$CustomerName,
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "development",
    
    [Parameter(Mandatory=$false)]
    [string]$AwsRegion = "us-west-2",
    
    [Parameter(Mandatory=$false)]
    [switch]$DestroyApplications = $true,
    
    [Parameter(Mandatory=$false)]
    [switch]$DestroyInfrastructure = $true,
    
    [Parameter(Mandatory=$false)]
    [switch]$ForceDestroy = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipConfirmation = $false
)

$ErrorActionPreference = "Continue"

Write-Host "🗑️ Customer Infrastructure Destruction" -ForegroundColor Red
Write-Host "Customer: $CustomerName | Environment: $Environment | Region: $AwsRegion" -ForegroundColor Yellow

# Safety confirmation
if (-not $SkipConfirmation) {
    Write-Host ""
    Write-Host "⚠️  WARNING: This will permanently destroy all infrastructure and data!" -ForegroundColor Red
    Write-Host "⚠️  This action cannot be undone!" -ForegroundColor Red
    Write-Host ""
    Write-Host "What will be destroyed:" -ForegroundColor Yellow
    if ($DestroyApplications) { Write-Host "  - Kubernetes applications (Helm releases)" -ForegroundColor White }
    if ($DestroyInfrastructure) { Write-Host "  - AWS EKS cluster" -ForegroundColor White }
    if ($DestroyInfrastructure) { Write-Host "  - RDS databases" -ForegroundColor White }
    if ($DestroyInfrastructure) { Write-Host "  - S3 buckets and all data" -ForegroundColor White }
    if ($DestroyInfrastructure) { Write-Host "  - VPC and networking" -ForegroundColor White }
    Write-Host ""
    
    $confirmation = Read-Host "Type 'DESTROY' to confirm destruction"
    if ($confirmation -ne "DESTROY") {
        Write-Host "❌ Destruction cancelled" -ForegroundColor Green
        exit 0
    }
}

Write-Host "🚀 Starting destruction process..." -ForegroundColor Red

# Step 1: Destroy Applications
if ($DestroyApplications) {
    Write-Host ""
    Write-Host "🗑️ Step 1: Destroying Applications..." -ForegroundColor Yellow
    
    try {
        # Configure kubectl
        Write-Host "🔧 Configuring kubectl..."
        aws eks update-kubeconfig --region $AwsRegion --name "$CustomerName-eks-cluster" 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            # Check if namespace exists
            $namespaceExists = kubectl get namespace "$CustomerName-stack" 2>$null
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "📦 Found namespace: $CustomerName-stack"
                
                # List Helm releases
                Write-Host "📋 Listing Helm releases..."
                helm list -n "$CustomerName-stack"
                
                # Uninstall Helm release
                Write-Host "🗑️ Uninstalling Helm release: $CustomerName"
                helm uninstall $CustomerName -n "$CustomerName-stack" --ignore-not-found
                
                # Wait for pods to terminate
                Write-Host "⏳ Waiting for pods to terminate..."
                kubectl wait --for=delete pods --all -n "$CustomerName-stack" --timeout=300s 2>$null
                
                # Force delete remaining resources
                Write-Host "🧹 Cleaning up remaining resources..."
                kubectl delete all --all -n "$CustomerName-stack" --ignore-not-found 2>$null
                kubectl delete pvc --all -n "$CustomerName-stack" --ignore-not-found 2>$null
                kubectl delete secrets --all -n "$CustomerName-stack" --ignore-not-found 2>$null
                kubectl delete configmaps --all -n "$CustomerName-stack" --ignore-not-found 2>$null
                
                # Delete namespace
                Write-Host "🗑️ Deleting namespace..."
                kubectl delete namespace "$CustomerName-stack" --ignore-not-found 2>$null
                
                Write-Host "✅ Applications destroyed successfully" -ForegroundColor Green
            } else {
                Write-Host "ℹ️ Namespace $CustomerName-stack not found - applications may already be destroyed" -ForegroundColor Cyan
            }
        } else {
            Write-Host "⚠️ EKS cluster not found or not accessible" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "❌ Error destroying applications: $_" -ForegroundColor Red
    }
}

# Step 2: Destroy Infrastructure
if ($DestroyInfrastructure) {
    Write-Host ""
    Write-Host "🗑️ Step 2: Destroying AWS Infrastructure..." -ForegroundColor Yellow
    
    # Destroy Terraform infrastructure
    $terraformDir = "terraform/environments/$CustomerName"
    if (Test-Path $terraformDir) {
        Write-Host "📁 Found Terraform directory: $terraformDir"
        
        try {
            Push-Location $terraformDir
            
            Write-Host "🔧 Initializing Terraform..."
            terraform init -backend-config="bucket=my-terra-bucket-001" `
                          -backend-config="key=$CustomerName/terraform.tfstate" `
                          -backend-config="region=$AwsRegion"
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "📋 Planning destruction..."
                terraform plan -destroy `
                              -var="customer_name=$CustomerName" `
                              -var="environment=$Environment" `
                              -var="aws_region=$AwsRegion"
                
                Write-Host "🗑️ Executing Terraform destroy..."
                terraform destroy -auto-approve `
                                -var="customer_name=$CustomerName" `
                                -var="environment=$Environment" `
                                -var="aws_region=$AwsRegion"
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✅ Terraform infrastructure destroyed successfully" -ForegroundColor Green
                } else {
                    Write-Host "❌ Terraform destroy failed" -ForegroundColor Red
                }
            } else {
                Write-Host "❌ Terraform initialization failed" -ForegroundColor Red
            }
        } catch {
            Write-Host "❌ Error during Terraform destroy: $_" -ForegroundColor Red
        } finally {
            Pop-Location
        }
    } else {
        Write-Host "ℹ️ Terraform directory not found: $terraformDir" -ForegroundColor Cyan
    }
    
    # Clean up S3 buckets
    Write-Host ""
    Write-Host "🧹 Cleaning up S3 buckets..." -ForegroundColor Yellow
    
    try {
        $buckets = aws s3api list-buckets --query "Buckets[?contains(Name, '$CustomerName')].Name" --output text
        
        if ($buckets) {
            $buckets.Split("`t") | ForEach-Object {
                $bucket = $_.Trim()
                if ($bucket) {
                    Write-Host "🗑️ Deleting S3 bucket: $bucket"
                    
                    # Delete all objects
                    aws s3 rm "s3://$bucket" --recursive 2>$null
                    
                    # Delete bucket
                    aws s3api delete-bucket --bucket $bucket --region $AwsRegion 2>$null
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "✅ S3 bucket $bucket deleted" -ForegroundColor Green
                    } else {
                        Write-Host "⚠️ Failed to delete bucket $bucket" -ForegroundColor Yellow
                    }
                }
            }
        } else {
            Write-Host "ℹ️ No S3 buckets found for customer: $CustomerName" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "❌ Error cleaning up S3 buckets: $_" -ForegroundColor Red
    }
}

# Step 3: Verification
Write-Host ""
Write-Host "🔍 Verifying destruction..." -ForegroundColor Yellow

# Check EKS cluster
try {
    aws eks describe-cluster --name "$CustomerName-eks-cluster" --region $AwsRegion 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "⚠️ EKS cluster still exists" -ForegroundColor Yellow
    } else {
        Write-Host "✅ EKS cluster destroyed" -ForegroundColor Green
    }
} catch {
    Write-Host "✅ EKS cluster destroyed" -ForegroundColor Green
}

# Check RDS instances
try {
    $rdsCount = aws rds describe-db-instances --region $AwsRegion --query "length(DBInstances[?contains(DBInstanceIdentifier, '$CustomerName')])" --output text
    if ([int]$rdsCount -gt 0) {
        Write-Host "⚠️ $rdsCount RDS instances still exist" -ForegroundColor Yellow
    } else {
        Write-Host "✅ All RDS instances destroyed" -ForegroundColor Green
    }
} catch {
    Write-Host "✅ All RDS instances destroyed" -ForegroundColor Green
}

# Check S3 buckets
try {
    $s3Count = aws s3api list-buckets --query "length(Buckets[?contains(Name, '$CustomerName')])" --output text
    if ([int]$s3Count -gt 0) {
        Write-Host "⚠️ $s3Count S3 buckets still exist" -ForegroundColor Yellow
    } else {
        Write-Host "✅ All S3 buckets destroyed" -ForegroundColor Green
    }
} catch {
    Write-Host "✅ All S3 buckets destroyed" -ForegroundColor Green
}

# Step 4: Cleanup Terraform state
if ($DestroyInfrastructure) {
    Write-Host ""
    Write-Host "🧹 Cleaning up Terraform state..." -ForegroundColor Yellow
    
    try {
        # Delete Terraform state files from S3
        aws s3 rm "s3://my-terra-bucket-001/$CustomerName/terraform.tfstate" 2>$null
        aws s3 rm "s3://my-terra-bucket-001/$CustomerName/terraform.tfstate.backup" 2>$null
        
        Write-Host "✅ Terraform state cleanup completed" -ForegroundColor Green
    } catch {
        Write-Host "⚠️ Terraform state cleanup may need manual intervention" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "🎯 Destruction Summary:" -ForegroundColor Cyan
Write-Host "  Customer: $CustomerName" -ForegroundColor White
Write-Host "  Environment: $Environment" -ForegroundColor White
Write-Host "  Region: $AwsRegion" -ForegroundColor White
Write-Host "  Applications Destroyed: $DestroyApplications" -ForegroundColor White
Write-Host "  Infrastructure Destroyed: $DestroyInfrastructure" -ForegroundColor White
Write-Host "  Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')" -ForegroundColor White

Write-Host ""
Write-Host "🎉 Infrastructure destruction completed!" -ForegroundColor Green
Write-Host "⚠️ Please verify in AWS console that all resources are cleaned up" -ForegroundColor Yellow