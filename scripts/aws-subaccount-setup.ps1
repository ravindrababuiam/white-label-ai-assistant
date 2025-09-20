# AWS Subaccount Setup Script
# This script creates and configures AWS subaccounts for customers

param(
    [Parameter(Mandatory=$true)]
    [string]$CustomerName,
    
    [Parameter(Mandatory=$true)]
    [string]$CustomerEmail,
    
    [Parameter(Mandatory=$false)]
    [string]$OrganizationId,
    
    [Parameter(Mandatory=$false)]
    [string]$BillingMode = "ALLOW_BILLING_ACCESS",
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun = $false
)

Write-Host "🏢 AWS Subaccount Setup for: $CustomerName" -ForegroundColor Green
Write-Host "Email: $CustomerEmail" -ForegroundColor Cyan

# Validate prerequisites
Write-Host "🔍 Validating prerequisites..." -ForegroundColor Yellow

# Check if AWS Organizations is available
try {
    $orgInfo = aws organizations describe-organization --query 'Organization.[Id,MasterAccountId]' --output text 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "AWS Organizations not available or not configured"
        exit 1
    }
    $orgId, $masterAccountId = $orgInfo -split "`t"
    Write-Host "✅ Organization ID: $orgId" -ForegroundColor Green
    Write-Host "✅ Master Account: $masterAccountId" -ForegroundColor Green
} catch {
    Write-Error "Failed to access AWS Organizations: $_"
    exit 1
}

# Generate account name
$accountName = "WhiteLabel-AI-$CustomerName"

if ($DryRun) {
    Write-Host "🔍 DRY RUN - Would create account: $accountName" -ForegroundColor Cyan
} else {
    # Create AWS account
    Write-Host "🏗️ Creating AWS subaccount..." -ForegroundColor Yellow
    
    try {
        $createResult = aws organizations create-account --email $CustomerEmail --account-name $accountName --query 'CreateAccountStatus.[Id,State,AccountId]' --output text
        $requestId, $state, $accountId = $createResult -split "`t"
        
        Write-Host "✅ Account creation initiated" -ForegroundColor Green
        Write-Host "Request ID: $requestId" -ForegroundColor Cyan
        
        # Wait for account creation to complete
        Write-Host "⏳ Waiting for account creation to complete..." -ForegroundColor Yellow
        
        do {
            Start-Sleep -Seconds 30
            $status = aws organizations describe-create-account-status --create-account-request-id $requestId --query 'CreateAccountStatus.[State,AccountId,FailureReason]' --output text
            $currentState, $currentAccountId, $failureReason = $status -split "`t"
            
            Write-Host "Status: $currentState" -ForegroundColor Cyan
            
            if ($currentState -eq "FAILED") {
                Write-Error "Account creation failed: $failureReason"
                exit 1
            }
        } while ($currentState -eq "IN_PROGRESS")
        
        if ($currentState -eq "SUCCEEDED") {
            $accountId = $currentAccountId
            Write-Host "✅ Account created successfully!" -ForegroundColor Green
            Write-Host "Account ID: $accountId" -ForegroundColor Green
        }
        
    } catch {
        Write-Error "Failed to create AWS account: $_"
        exit 1
    }
}

# Create Organizational Unit for customer accounts
Write-Host "📁 Setting up Organizational Unit..." -ForegroundColor Yellow

if (-not $DryRun) {
    try {
        # Check if OU already exists
        $existingOUs = aws organizations list-organizational-units-for-parent --parent-id $orgId --query 'OrganizationalUnits[?Name==`Customer-Accounts`].Id' --output text
        
        if ([string]::IsNullOrEmpty($existingOUs)) {
            # Create OU
            $ouResult = aws organizations create-organizational-unit --parent-id $orgId --name "Customer-Accounts" --query 'OrganizationalUnit.Id' --output text
            Write-Host "✅ Created Organizational Unit: $ouResult" -ForegroundColor Green
            $ouId = $ouResult
        } else {
            $ouId = $existingOUs
            Write-Host "✅ Using existing Organizational Unit: $ouId" -ForegroundColor Green
        }
        
        # Move account to OU
        aws organizations move-account --account-id $accountId --source-parent-id $orgId --destination-parent-id $ouId
        Write-Host "✅ Account moved to Customer-Accounts OU" -ForegroundColor Green
        
    } catch {
        Write-Warning "Failed to setup Organizational Unit: $_"
    }
}

# Create IAM role for cross-account access
Write-Host "🔐 Setting up cross-account access..." -ForegroundColor Yellow

$crossAccountRolePolicy = @"
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::$masterAccountId:root"
            },
            "Action": "sts:AssumeRole",
            "Condition": {
                "StringEquals": {
                    "sts:ExternalId": "$CustomerName-external-id"
                }
            }
        }
    ]
}
"@

$managementPolicy = @"
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:*",
                "eks:*",
                "rds:*",
                "elasticache:*",
                "s3:*",
                "iam:*",
                "cloudformation:*",
                "logs:*",
                "monitoring:*"
            ],
            "Resource": "*"
        }
    ]
}
"@

# Create setup script for the new account
$accountSetupScript = @"
#!/bin/bash
# Account setup script for customer: $CustomerName
# Run this script in the new AWS account

CUSTOMER_NAME="$CustomerName"
ACCOUNT_ID="$accountId"
MASTER_ACCOUNT_ID="$masterAccountId"

echo "🔧 Setting up AWS account for customer: \$CUSTOMER_NAME"

# Create cross-account role
echo "Creating cross-account management role..."
aws iam create-role --role-name CustomerManagementRole --assume-role-policy-document '$crossAccountRolePolicy'

# Attach management policy
echo "Attaching management policy..."
aws iam put-role-policy --role-name CustomerManagementRole --policy-name CustomerManagementPolicy --policy-document '$managementPolicy'

# Create S3 bucket for Terraform state
echo "Creating Terraform state bucket..."
BUCKET_NAME="terraform-state-\$CUSTOMER_NAME-\$(date +%s)"
aws s3 mb s3://\$BUCKET_NAME --region us-west-2

# Enable versioning
aws s3api put-bucket-versioning --bucket \$BUCKET_NAME --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
echo "Creating DynamoDB table for state locking..."
aws dynamodb create-table --table-name terraform-state-locks --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 --region us-west-2

echo "✅ Account setup completed!"
echo "Terraform state bucket: \$BUCKET_NAME"
echo "Cross-account role ARN: arn:aws:iam::\$ACCOUNT_ID:role/CustomerManagementRole"
"@

if (-not $DryRun) {
    $accountSetupScript | Out-File -FilePath "scripts/setup-account-$CustomerName.sh" -Encoding UTF8
    
    if ($IsLinux -or $IsMacOS) {
        chmod +x "scripts/setup-account-$CustomerName.sh"
    }
}

# Create customer configuration template
Write-Host "📋 Creating customer configuration..." -ForegroundColor Yellow

$customerConfig = @"
# Customer Configuration: $CustomerName
# Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

[Customer]
Name = "$CustomerName"
Email = "$CustomerEmail"
AccountId = "$accountId"
Environment = "production"

[AWS]
Region = "us-west-2"
OrganizationId = "$orgId"
OrganizationalUnit = "Customer-Accounts"

[Access]
CrossAccountRoleArn = "arn:aws:iam::$accountId:role/CustomerManagementRole"
ExternalId = "$CustomerName-external-id"

[Infrastructure]
VpcCidr = "10.0.0.0/16"
EnableGpu = false
NodeInstanceTypes = ["t3.medium"]

[Billing]
Mode = "$BillingMode"
CostCenter = "$CustomerName"

[Security]
EncryptionEnabled = true
BackupEnabled = true
MonitoringEnabled = true

[Terraform]
StateBucket = "terraform-state-$CustomerName"
StateKey = "customers/$CustomerName/terraform.tfstate"
LockTable = "terraform-state-locks"
"@

if (-not $DryRun) {
    $customerConfig | Out-File -FilePath "customers/$CustomerName.conf" -Encoding UTF8
}

# Create deployment instructions
$instructions = @"
# AWS Subaccount Setup Complete

## Customer: $CustomerName
## Account ID: $accountId
## Email: $CustomerEmail

### Next Steps:

1. **Account Setup**
   ```bash
   # Switch to the new account
   aws sts assume-role --role-arn arn:aws:iam::$accountId:role/OrganizationAccountAccessRole --role-session-name setup-session
   
   # Run account setup script
   ./scripts/setup-account-$CustomerName.sh
   ```

2. **Deploy Infrastructure**
   ```bash
   # Run customer onboarding
   ./scripts/customer-onboarding.ps1 -CustomerName "$CustomerName" -AwsRegion "us-west-2"
   ```

3. **Validate Deployment**
   ```bash
   # Run validation
   cd terraform/environments/$CustomerName
   ./validate.sh
   ```

### Account Details:
- **Account ID**: $accountId
- **Organization**: $orgId
- **OU**: Customer-Accounts
- **Cross-Account Role**: arn:aws:iam::$accountId:role/CustomerManagementRole

### Security Notes:
- Cross-account access configured with external ID
- All resources will be encrypted
- Billing access: $BillingMode
- Monitoring and logging enabled

### Support:
- Configuration file: customers/$CustomerName.conf
- Setup script: scripts/setup-account-$CustomerName.sh
- Terraform workspace: terraform/environments/$CustomerName

---
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@

Write-Host $instructions -ForegroundColor White

if (-not $DryRun) {
    $instructions | Out-File -FilePath "customers/$CustomerName-setup-instructions.md" -Encoding UTF8
    
    Write-Host "✅ AWS Subaccount setup completed!" -ForegroundColor Green
    Write-Host "📋 Instructions saved to: customers/$CustomerName-setup-instructions.md" -ForegroundColor Cyan
    Write-Host "🔧 Setup script created: scripts/setup-account-$CustomerName.sh" -ForegroundColor Cyan
    Write-Host "⚙️ Configuration saved: customers/$CustomerName.conf" -ForegroundColor Cyan
}

Write-Host "🎯 Ready for infrastructure deployment!" -ForegroundColor Green