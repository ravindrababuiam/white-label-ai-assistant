# Helm Chart Deployment Script for Customer Stack
param(
    [Parameter(Mandatory=$true)]
    [string]$CustomerName,
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "production",
    
    [Parameter(Mandatory=$false)]
    [string]$Namespace = "",
    
    [Parameter(Mandatory=$false)]
    [string]$AwsRegion = "us-west-2",
    
    [Parameter(Mandatory=$false)]
    [switch]$EnableGpu = $false,
    
    [Parameter(Mandatory=$false)]
    [string]$ValuesFile = "",
    
    [Parameter(Mandatory=$false)]
    [hashtable]$SetValues = @{},
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$Upgrade = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$EnableDebug = $false
)

$ErrorActionPreference = "Stop"

Write-Host "Helm Chart Deployment for Customer: $CustomerName" -ForegroundColor Green
Write-Host "Environment: $Environment | Region: $AwsRegion" -ForegroundColor Cyan

# Set default namespace if not provided
if ([string]::IsNullOrEmpty($Namespace)) {
    $Namespace = "$CustomerName-stack"
}

# Validate Helm installation
try {
    $helmVersion = helm version --short
    Write-Host "Helm version: $helmVersion" -ForegroundColor Green
} catch {
    Write-Error "Helm is not installed or not in PATH"
    exit 1
}

# Validate kubectl context
try {
    $currentContext = kubectl config current-context
    Write-Host "Kubectl context: $currentContext" -ForegroundColor Green
} catch {
    Write-Error "kubectl is not configured or no current context"
    exit 1
}

# Check if release already exists
Write-Host "Checking if Helm release exists..." -ForegroundColor Cyan
$releaseExists = $false
try {
    $existingRelease = helm list -n $Namespace -q | Where-Object { $_ -eq $CustomerName }
    if ($existingRelease) {
        $releaseExists = $true
        Write-Host "Helm release '$CustomerName' already exists, will upgrade" -ForegroundColor Yellow
    } else {
        Write-Host "No existing release found, will install" -ForegroundColor Green
    }
} catch {
    Write-Host "No existing release found, will install" -ForegroundColor Green
}# Bui
ld Helm command
$helmCommand = @("helm")

if ($Upgrade -or $releaseExists) {
    $helmCommand += @("upgrade", "--install")
} else {
    $helmCommand += "install"
}

$helmCommand += @(
    $CustomerName,
    "helm-charts/customer-stack",
    "--namespace", $Namespace,
    "--create-namespace"
)

# Add values files
$valuesFiles = @()
$valuesFiles += "helm-charts/customer-stack/values.yaml"

if ($Environment -eq "production") {
    $valuesFiles += "helm-charts/customer-stack/values-production.yaml"
}

if ($EnableGpu) {
    $valuesFiles += "helm-charts/customer-stack/values-gpu.yaml"
}

if (-not [string]::IsNullOrEmpty($ValuesFile) -and (Test-Path $ValuesFile)) {
    $valuesFiles += $ValuesFile
}

# Add values files to command
foreach ($file in $valuesFiles) {
    if (Test-Path $file) {
        $helmCommand += @("--values", $file)
        Write-Host "Using values file: $file" -ForegroundColor Cyan
    } else {
        Write-Warning "Values file not found: $file"
    }
}

# Get AWS resource information from Terraform
$terraformDir = "terraform/environments/$CustomerName"
if (Test-Path $terraformDir) {
    Write-Host "Getting AWS resource information from Terraform..." -ForegroundColor Yellow
    
    try {
        Push-Location $terraformDir
        
        $rdsEndpoints = terraform output -json | ConvertFrom-Json
        if ($rdsEndpoints.PSObject.Properties.Name -contains "rds_litellm_endpoint") {
            $SetValues["aws.rds.endpoints.litellm"] = $rdsEndpoints.rds_litellm_endpoint.value
        }
        if ($rdsEndpoints.PSObject.Properties.Name -contains "rds_lago_endpoint") {
            $SetValues["aws.rds.endpoints.lago"] = $rdsEndpoints.rds_lago_endpoint.value
        }
        
        Write-Host "AWS resource information retrieved" -ForegroundColor Green
        
    } catch {
        Write-Warning "Failed to get Terraform outputs: $_"
    } finally {
        Pop-Location
    }
} else {
    Write-Warning "Terraform directory not found: $terraformDir"
}

# Add required set values
$SetValues["global.customerName"] = $CustomerName
$SetValues["global.environment"] = $Environment
$SetValues["global.region"] = $AwsRegion
$SetValues["global.aws.region"] = $AwsRegion

# Add set values to command
foreach ($key in $SetValues.Keys) {
    $value = $SetValues[$key]
    $helmCommand += @("--set", "$key=$value")
}

# Add additional flags
if ($DryRun) {
    $helmCommand += "--dry-run"
}

if ($EnableDebug) {
    $helmCommand += "--debug"
}

$helmCommand += @("--wait", "--timeout", "10m")

# Display command for debugging
if ($EnableDebug) {
    Write-Host "Helm command:" -ForegroundColor Yellow
    Write-Host ($helmCommand -join " ") -ForegroundColor White
}

# Execute Helm command
Write-Host "Deploying customer stack..." -ForegroundColor Yellow

try {
    if ($DryRun) {
        Write-Host "DRY RUN - Validating Helm chart..." -ForegroundColor Cyan
    }
    
    $result = & $helmCommand[0] $helmCommand[1..($helmCommand.Length-1)]
    
    if ($LASTEXITCODE -eq 0) {
        if ($DryRun) {
            Write-Host "Helm chart validation successful!" -ForegroundColor Green
        } else {
            Write-Host "Customer stack deployed successfully!" -ForegroundColor Green
        }
    } else {
        Write-Error "Helm deployment failed with exit code: $LASTEXITCODE"
    }
    
} catch {
    Write-Error "Helm deployment failed: $_"
    exit 1
}

# Post-deployment validation (if not dry run)
if (-not $DryRun) {
    Write-Host "Validating deployment..." -ForegroundColor Yellow
    
    try {
        kubectl wait --for=condition=Ready pods --all -n $Namespace --timeout=300s
        Write-Host "All pods are ready" -ForegroundColor Green
    } catch {
        Write-Warning "Some pods may not be ready yet: $_"
    }
    
    Write-Host "Pod status:" -ForegroundColor Cyan
    kubectl get pods -n $Namespace
    
    Write-Host "Service status:" -ForegroundColor Cyan
    kubectl get services -n $Namespace
    
    $loadBalancerUrl = ""
    try {
        $loadBalancerUrl = kubectl get service open-webui-service -n $Namespace -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
        if ($loadBalancerUrl) {
            Write-Host "Application URL: http://$loadBalancerUrl:8080" -ForegroundColor Green
        } else {
            Write-Host "LoadBalancer URL not yet available" -ForegroundColor Yellow
        }
    } catch {
        Write-Warning "Could not retrieve LoadBalancer URL"
    }
    
    Write-Host "Helm release information:" -ForegroundColor Cyan
    helm list -n $Namespace
    
    Write-Host "Deployment completed!" -ForegroundColor Green
}

Write-Host "Deployment script completed successfully!" -ForegroundColor Green