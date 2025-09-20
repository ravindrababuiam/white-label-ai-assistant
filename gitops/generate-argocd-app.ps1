# Generate ArgoCD Application for Customer
# This script creates ArgoCD Application manifests for customer deployments

param(
    [Parameter(Mandatory=$true)]
    [string]$CustomerName,
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "production",
    
    [Parameter(Mandatory=$false)]
    [string]$AwsRegion = "us-west-2",
    
    [Parameter(Mandatory=$false)]
    [string]$AwsAccountId = "",
    
    [Parameter(Mandatory=$false)]
    [string]$GitRepository = "https://github.com/your-org/white-label-ai-assistant",
    
    [Parameter(Mandatory=$false)]
    [string]$GitBranch = "main",
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "gitops/applications",
    
    [Parameter(Mandatory=$false)]
    [switch]$EnableGpu = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun = $false
)

$ErrorActionPreference = "Stop"

Write-Host "🚀 Generating ArgoCD Application for Customer: $CustomerName" -ForegroundColor Green
Write-Host "Environment: $Environment | Region: $AwsRegion" -ForegroundColor Cyan

# Validate customer name format
if ($CustomerName -notmatch '^[a-z0-9-]+$') {
    Write-Error "Customer name must contain only lowercase letters, numbers, and hyphens"
    exit 1
}

# Create output directory
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# Get AWS resource information from Terraform
$terraformDir = "terraform/environments/$CustomerName"
$awsResources = @{}

if (Test-Path $terraformDir) {
    Write-Host "🔍 Getting AWS resource information from Terraform..." -ForegroundColor Yellow
    
    try {
        Push-Location $terraformDir
        
        # Get Terraform outputs
        $terraformOutputs = terraform output -json | ConvertFrom-Json
        
        # Extract resource information
        if ($terraformOutputs.PSObject.Properties.Name -contains "s3_documents_bucket") {
            $awsResources["S3_DOCUMENTS_BUCKET"] = $terraformOutputs.s3_documents_bucket.value
        }
        if ($terraformOutputs.PSObject.Properties.Name -contains "s3_data_bucket") {
            $awsResources["S3_DATA_BUCKET"] = $terraformOutputs.s3_data_bucket.value
        }
        if ($terraformOutputs.PSObject.Properties.Name -contains "rds_litellm_endpoint") {
            $awsResources["RDS_LITELLM_ENDPOINT"] = $terraformOutputs.rds_litellm_endpoint.value
        }
        if ($terraformOutputs.PSObject.Properties.Name -contains "rds_lago_endpoint") {
            $awsResources["RDS_LAGO_ENDPOINT"] = $terraformOutputs.rds_lago_endpoint.value
        }
        if ($terraformOutputs.PSObject.Properties.Name -contains "redis_litellm_endpoint") {
            $awsResources["REDIS_LITELLM_ENDPOINT"] = $terraformOutputs.redis_litellm_endpoint.value
        }
        if ($terraformOutputs.PSObject.Properties.Name -contains "redis_lago_endpoint") {
            $awsResources["REDIS_LAGO_ENDPOINT"] = $terraformOutputs.redis_lago_endpoint.value
        }
        if ($terraformOutputs.PSObject.Properties.Name -contains "service_account_role_arn") {
            $awsResources["SERVICE_ACCOUNT_ROLE_ARN"] = $terraformOutputs.service_account_role_arn.value
        }
        
        # Get AWS Account ID if not provided
        if ([string]::IsNullOrEmpty($AwsAccountId)) {
            $AwsAccountId = aws sts get-caller-identity --query 'Account' --output text 2>$null
        }
        
        Write-Host "✅ AWS resource information retrieved" -ForegroundColor Green
        
    } catch {
        Write-Warning "Failed to get Terraform outputs: $_"
    } finally {
        Pop-Location
    }
} else {
    Write-Warning "Terraform directory not found: $terraformDir"
}

# Set default values for missing resources
$defaultResources = @{
    "S3_DOCUMENTS_BUCKET" = "$CustomerName-documents-$(Get-Random -Minimum 1000 -Maximum 9999)"
    "S3_DATA_BUCKET" = "$CustomerName-data-$(Get-Random -Minimum 1000 -Maximum 9999)"
    "RDS_LITELLM_ENDPOINT" = "$CustomerName-litellm-db.region.rds.amazonaws.com"
    "RDS_LAGO_ENDPOINT" = "$CustomerName-lago-db.region.rds.amazonaws.com"
    "REDIS_LITELLM_ENDPOINT" = "$CustomerName-litellm-redis.cache.amazonaws.com"
    "REDIS_LAGO_ENDPOINT" = "$CustomerName-lago-redis.cache.amazonaws.com"
    "SERVICE_ACCOUNT_ROLE_ARN" = "arn:aws:iam::$AwsAccountId:role/$CustomerName-service-role"
}

foreach ($key in $defaultResources.Keys) {
    if (-not $awsResources.ContainsKey($key)) {
        $awsResources[$key] = $defaultResources[$key]
        Write-Host "⚠️ Using default value for $key`: $($defaultResources[$key])" -ForegroundColor Yellow
    }
}

# Read the application template
$templatePath = "gitops/argocd/application-template.yaml"
if (-not (Test-Path $templatePath)) {
    Write-Error "Application template not found: $templatePath"
    exit 1
}

$applicationTemplate = Get-Content $templatePath -Raw

# Replace placeholders in template
$replacements = @{
    "CUSTOMER_NAME" = $CustomerName
    "ENVIRONMENT" = $Environment
    "AWS_REGION" = $AwsRegion
    "AWS_ACCOUNT_ID" = $AwsAccountId
    "GIT_REPOSITORY" = $GitRepository
    "GIT_BRANCH" = $GitBranch
}

# Add AWS resource replacements
foreach ($key in $awsResources.Keys) {
    $replacements[$key] = $awsResources[$key]
}

# Perform replacements
$applicationManifest = $applicationTemplate
foreach ($key in $replacements.Keys) {
    $applicationManifest = $applicationManifest -replace $key, $replacements[$key]
}

# Add GPU-specific parameters if enabled
if ($EnableGpu) {
    $gpuParameters = @"
        - name: ollama.gpu.enabled
          value: "true"
        - name: ollama.nodeSelector.accelerator
          value: "nvidia-tesla-k80"
"@
    
    # Insert GPU parameters before the destination section
    $applicationManifest = $applicationManifest -replace "(  destination:)", "$gpuParameters`n`$1"
}

# Generate output filename
$outputFile = "$OutputPath/$CustomerName-$Environment.yaml"

if ($DryRun) {
    Write-Host "🔍 DRY RUN - Generated ArgoCD Application:" -ForegroundColor Cyan
    Write-Host $applicationManifest -ForegroundColor White
} else {
    # Write the application manifest
    $applicationManifest | Out-File -FilePath $outputFile -Encoding UTF8
    Write-Host "✅ ArgoCD Application generated: $outputFile" -ForegroundColor Green
}

# Generate ApplicationSet for multiple environments (if needed)
$appSetTemplate = @"
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: customer-$CustomerName-environments
  namespace: argocd
  labels:
    customer: $CustomerName
    app.kubernetes.io/part-of: white-label-ai-assistant
spec:
  generators:
  - list:
      elements:
      - environment: production
        region: $AwsRegion
        accountId: $AwsAccountId
      - environment: staging
        region: $AwsRegion
        accountId: $AwsAccountId
  template:
    metadata:
      name: customer-stack-$CustomerName-{{environment}}
      labels:
        customer: $CustomerName
        environment: '{{environment}}'
    spec:
      project: customer-environments
      source:
        repoURL: $GitRepository
        targetRevision: $GitBranch
        path: helm-charts/customer-stack
        helm:
          valueFiles:
            - values.yaml
            - values-{{environment}}.yaml
          parameters:
            - name: global.customerName
              value: $CustomerName
            - name: global.environment
              value: '{{environment}}'
            - name: global.region
              value: '{{region}}'
            - name: global.aws.region
              value: '{{region}}'
            - name: global.aws.accountId
              value: '{{accountId}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: $CustomerName-stack
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
"@

$appSetFile = "$OutputPath/$CustomerName-applicationset.yaml"
if (-not $DryRun) {
    $appSetTemplate | Out-File -FilePath $appSetFile -Encoding UTF8
    Write-Host "✅ ApplicationSet generated: $appSetFile" -ForegroundColor Green
}

# Generate sync wave configuration
$syncWaveConfig = @"
# Sync Wave Configuration for $CustomerName
# This defines the order of resource deployment

apiVersion: v1
kind: ConfigMap
metadata:
  name: $CustomerName-sync-waves
  namespace: argocd
  labels:
    customer: $CustomerName
    app.kubernetes.io/part-of: white-label-ai-assistant
data:
  sync-waves.yaml: |
    # Wave 0: Infrastructure prerequisites
    - name: namespace
      wave: 0
    - name: serviceaccount
      wave: 0
    - name: secrets
      wave: 0
    - name: configmaps
      wave: 0
    
    # Wave 1: Storage and databases
    - name: persistent-volume-claims
      wave: 1
    
    # Wave 2: Core services
    - name: qdrant
      wave: 2
    - name: ollama
      wave: 2
    
    # Wave 3: Applications
    - name: open-webui
      wave: 3
    
    # Wave 4: Initialization jobs
    - name: model-init-job
      wave: 4
    - name: collection-init-job
      wave: 4
    
    # Wave 5: Networking and policies
    - name: services
      wave: 5
    - name: network-policies
      wave: 5
    - name: pod-disruption-budgets
      wave: 5
"@

$syncWaveFile = "$OutputPath/$CustomerName-sync-waves.yaml"
if (-not $DryRun) {
    $syncWaveConfig | Out-File -FilePath $syncWaveFile -Encoding UTF8
    Write-Host "✅ Sync wave configuration generated: $syncWaveFile" -ForegroundColor Green
}

# Generate health check configuration
$healthCheckConfig = @"
apiVersion: v1
kind: ConfigMap
metadata:
  name: $CustomerName-health-checks
  namespace: argocd
  labels:
    customer: $CustomerName
    app.kubernetes.io/part-of: white-label-ai-assistant
data:
  health-checks.yaml: |
    # Custom health checks for customer applications
    open-webui:
      healthCheck:
        http:
          path: /health
          port: 8080
        initialDelaySeconds: 30
        periodSeconds: 10
    
    ollama:
      healthCheck:
        http:
          path: /api/tags
          port: 11434
        initialDelaySeconds: 60
        periodSeconds: 30
    
    qdrant:
      healthCheck:
        http:
          path: /health
          port: 6333
        initialDelaySeconds: 30
        periodSeconds: 15
"@

$healthCheckFile = "$OutputPath/$CustomerName-health-checks.yaml"
if (-not $DryRun) {
    $healthCheckConfig | Out-File -FilePath $healthCheckFile -Encoding UTF8
    Write-Host "✅ Health check configuration generated: $healthCheckFile" -ForegroundColor Green
}

# Generate deployment summary
$deploymentSummary = @"
# ArgoCD Application Generation Summary

## Customer Information
- **Customer**: $CustomerName
- **Environment**: $Environment
- **Region**: $AwsRegion
- **Account ID**: $AwsAccountId
- **GPU Enabled**: $EnableGpu

## Generated Files
- **Application**: $outputFile
- **ApplicationSet**: $appSetFile
- **Sync Waves**: $syncWaveFile
- **Health Checks**: $healthCheckFile

## AWS Resources
$(foreach ($key in $awsResources.Keys) {
    "- **$key**: $($awsResources[$key])"
})

## GitOps Configuration
- **Repository**: $GitRepository
- **Branch**: $GitBranch
- **Chart Path**: helm-charts/customer-stack

## Deployment Commands
```bash
# Apply ArgoCD Application
kubectl apply -f $outputFile

# Apply ApplicationSet (for multi-environment)
kubectl apply -f $appSetFile

# Apply configurations
kubectl apply -f $syncWaveFile
kubectl apply -f $healthCheckFile

# Check application status
argocd app get customer-stack-$CustomerName

# Sync application
argocd app sync customer-stack-$CustomerName
```

## Monitoring
- ArgoCD UI: https://argocd.your-domain.com/applications/customer-stack-$CustomerName
- Application Namespace: $CustomerName-stack

---
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Status: $($DryRun ? 'DRY RUN' : 'GENERATED')
"@

$summaryFile = "$OutputPath/$CustomerName-summary.md"
if (-not $DryRun) {
    $deploymentSummary | Out-File -FilePath $summaryFile -Encoding UTF8
    Write-Host "📋 Deployment summary saved: $summaryFile" -ForegroundColor Cyan
}

Write-Host "🎯 ArgoCD Application generation completed!" -ForegroundColor Green

if ($DryRun) {
    Write-Host "🔍 DRY RUN completed - no files were created" -ForegroundColor Cyan
} else {
    Write-Host "📁 Generated files in: $OutputPath" -ForegroundColor Cyan
    Write-Host "🚀 Ready for GitOps deployment!" -ForegroundColor Green
}
 