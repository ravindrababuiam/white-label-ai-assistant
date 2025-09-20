# Sync ArgoCD Applications
# This script manages ArgoCD application synchronization

param(
    [Parameter(Mandatory=$false)]
    [string]$CustomerName = "",
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "",
    
    [Parameter(Mandatory=$false)]
    [string]$ArgocdServer = "argocd.your-domain.com",
    
    [Parameter(Mandatory=$false)]
    [string]$ArgocdNamespace = "argocd",
    
    [Parameter(Mandatory=$false)]
    [switch]$SyncAll = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$Prune = $false
)

$ErrorActionPreference = "Stop"

Write-Host "🔄 ArgoCD Application Sync Manager" -ForegroundColor Green
Write-Host "=================================" -ForegroundColor Green

# Check if ArgoCD CLI is available
try {
    $argocdVersion = argocd version --client --short 2>$null
    Write-Host "✅ ArgoCD CLI version: $argocdVersion" -ForegroundColor Green
} catch {
    Write-Error "ArgoCD CLI is not installed or not in PATH"
    exit 1
}

# Check if kubectl is configured
try {
    $currentContext = kubectl config current-context
    Write-Host "✅ Kubectl context: $currentContext" -ForegroundColor Green
} catch {
    Write-Error "kubectl is not configured or no current context"
    exit 1
}

# Login to ArgoCD (assumes token-based auth or existing login)
Write-Host "🔐 Checking ArgoCD authentication..." -ForegroundColor Yellow
try {
    $argocdContext = argocd context
    Write-Host "✅ ArgoCD authentication verified" -ForegroundColor Green
} catch {
    Write-Warning "ArgoCD authentication may be required"
    Write-Host "Please run: argocd login $ArgocdServer" -ForegroundColor Cyan
}

# Function to get applications
function Get-ArgocdApplications {
    param(
        [string]$CustomerFilter = "",
        [string]$EnvironmentFilter = ""
    )
    
    $selector = @()
    
    if ($CustomerFilter) {
        $selector += "customer=$CustomerFilter"
    }
    
    if ($EnvironmentFilter) {
        $selector += "environment=$EnvironmentFilter"
    }
    
    $selectorString = if ($selector.Count -gt 0) { $selector -join "," } else { "" }
    
    if ($selectorString) {
        $apps = argocd app list --selector $selectorString -o json | ConvertFrom-Json
    } else {
        $apps = argocd app list -o json | ConvertFrom-Json
    }
    
    return $apps
}

# Function to sync application
function Sync-ArgocdApplication {
    param(
        [string]$AppName,
        [bool]$DryRunMode = $false,
        [bool]$ForceSync = $false,
        [bool]$PruneResources = $false
    )
    
    $syncArgs = @("argocd", "app", "sync", $AppName)
    
    if ($DryRunMode) {
        $syncArgs += "--dry-run"
    }
    
    if ($ForceSync) {
        $syncArgs += "--force"
    }
    
    if ($PruneResources) {
        $syncArgs += "--prune"
    }
    
    $syncArgs += @("--timeout", "600")
    
    Write-Host "🔄 Syncing application: $AppName" -ForegroundColor Cyan
    
    if ($DryRunMode) {
        Write-Host "🔍 DRY RUN - Would execute: $($syncArgs -join ' ')" -ForegroundColor Yellow
        return $true
    }
    
    try {
        & $syncArgs[0] $syncArgs[1..($syncArgs.Length-1)]
        Write-Host "✅ Successfully synced: $AppName" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "❌ Failed to sync: $AppName - $_" -ForegroundColor Red
        return $false
    }
}

# Function to check application health
function Test-ArgocdApplicationHealth {
    param(
        [string]$AppName
    )
    
    try {
        $appInfo = argocd app get $AppName -o json | ConvertFrom-Json
        
        $health = $appInfo.status.health.status
        $sync = $appInfo.status.sync.status
        
        $healthIcon = switch ($health) {
            "Healthy" { "✅" }
            "Progressing" { "🔄" }
            "Degraded" { "⚠️" }
            "Suspended" { "⏸️" }
            default { "❓" }
        }
        
        $syncIcon = switch ($sync) {
            "Synced" { "✅" }
            "OutOfSync" { "🔄" }
            "Unknown" { "❓" }
            default { "❓" }
        }
        
        Write-Host "  $healthIcon Health: $health | $syncIcon Sync: $sync" -ForegroundColor Cyan
        
        return @{
            Health = $health
            Sync = $sync
            Healthy = ($health -eq "Healthy")
            InSync = ($sync -eq "Synced")
        }
    } catch {
        Write-Host "  ❌ Failed to get application status: $_" -ForegroundColor Red
        return @{
            Health = "Unknown"
            Sync = "Unknown"
            Healthy = $false
            InSync = $false
        }
    }
}

# Get applications to sync
Write-Host "🔍 Discovering ArgoCD applications..." -ForegroundColor Yellow

$applications = Get-ArgocdApplications -CustomerFilter $CustomerName -EnvironmentFilter $Environment

if ($applications.Count -eq 0) {
    Write-Host "⚠️ No applications found matching criteria" -ForegroundColor Yellow
    exit 0
}

Write-Host "📋 Found $($applications.Count) applications:" -ForegroundColor Cyan
foreach ($app in $applications) {
    $customer = $app.metadata.labels.customer
    $environment = $app.metadata.labels.environment
    Write-Host "  • $($app.metadata.name) (Customer: $customer, Environment: $environment)" -ForegroundColor White
}

# Check current application status
Write-Host "`n📊 Current Application Status:" -ForegroundColor Yellow
$statusSummary = @{
    Total = $applications.Count
    Healthy = 0
    InSync = 0
    NeedsSync = 0
}

foreach ($app in $applications) {
    Write-Host "🔍 $($app.metadata.name):" -ForegroundColor White
    $status = Test-ArgocdApplicationHealth -AppName $app.metadata.name
    
    if ($status.Healthy) { $statusSummary.Healthy++ }
    if ($status.InSync) { $statusSummary.InSync++ }
    if (-not $status.InSync) { $statusSummary.NeedsSync++ }
}

Write-Host "`n📈 Status Summary:" -ForegroundColor Cyan
Write-Host "  Total Applications: $($statusSummary.Total)" -ForegroundColor White
Write-Host "  Healthy: $($statusSummary.Healthy)" -ForegroundColor Green
Write-Host "  In Sync: $($statusSummary.InSync)" -ForegroundColor Green
Write-Host "  Need Sync: $($statusSummary.NeedsSync)" -ForegroundColor Yellow

# Perform synchronization
if ($SyncAll -or $statusSummary.NeedsSync -gt 0) {
    Write-Host "`n🚀 Starting Application Synchronization..." -ForegroundColor Green
    
    $syncResults = @{
        Success = 0
        Failed = 0
        Skipped = 0
    }
    
    foreach ($app in $applications) {
        $appName = $app.metadata.name
        
        # Check if sync is needed (unless forcing)
        if (-not $Force) {
            $status = Test-ArgocdApplicationHealth -AppName $appName
            if ($status.InSync) {
                Write-Host "⏭️ Skipping $appName (already in sync)" -ForegroundColor Gray
                $syncResults.Skipped++
                continue
            }
        }
        
        # Perform sync
        $syncSuccess = Sync-ArgocdApplication -AppName $appName -DryRunMode $DryRun -ForceSync $Force -PruneResources $Prune
        
        if ($syncSuccess) {
            $syncResults.Success++
        } else {
            $syncResults.Failed++
        }
        
        # Wait between syncs to avoid overwhelming the cluster
        if (-not $DryRun) {
            Start-Sleep -Seconds 5
        }
    }
    
    Write-Host "`n📊 Synchronization Results:" -ForegroundColor Cyan
    Write-Host "  ✅ Successful: $($syncResults.Success)" -ForegroundColor Green
    Write-Host "  ❌ Failed: $($syncResults.Failed)" -ForegroundColor Red
    Write-Host "  ⏭️ Skipped: $($syncResults.Skipped)" -ForegroundColor Gray
    
} else {
    Write-Host "`n✅ All applications are in sync - no action needed" -ForegroundColor Green
}

# Post-sync validation
if (-not $DryRun -and ($SyncAll -or $statusSummary.NeedsSync -gt 0)) {
    Write-Host "`n🔍 Post-Sync Validation..." -ForegroundColor Yellow
    
    # Wait for applications to stabilize
    Write-Host "⏳ Waiting for applications to stabilize..." -ForegroundColor Cyan
    Start-Sleep -Seconds 30
    
    $postSyncSummary = @{
        Total = $applications.Count
        Healthy = 0
        InSync = 0
        Issues = 0
    }
    
    foreach ($app in $applications) {
        Write-Host "🔍 Validating $($app.metadata.name):" -ForegroundColor White
        $status = Test-ArgocdApplicationHealth -AppName $app.metadata.name
        
        if ($status.Healthy) { $postSyncSummary.Healthy++ }
        if ($status.InSync) { $postSyncSummary.InSync++ }
        if (-not $status.Healthy -or -not $status.InSync) { $postSyncSummary.Issues++ }
    }
    
    Write-Host "`n📈 Post-Sync Summary:" -ForegroundColor Cyan
    Write-Host "  Total Applications: $($postSyncSummary.Total)" -ForegroundColor White
    Write-Host "  Healthy: $($postSyncSummary.Healthy)" -ForegroundColor Green
    Write-Host "  In Sync: $($postSyncSummary.InSync)" -ForegroundColor Green
    Write-Host "  Issues: $($postSyncSummary.Issues)" -ForegroundColor $(if($postSyncSummary.Issues -eq 0) {"Green"} else {"Red"})
    
    if ($postSyncSummary.Issues -eq 0) {
        Write-Host "🎉 All applications are healthy and in sync!" -ForegroundColor Green
    } else {
        Write-Host "⚠️ Some applications have issues - manual investigation may be required" -ForegroundColor Yellow
    }
}

# Generate sync report
$syncReport = @"
# ArgoCD Sync Report

## Sync Information
- **Date**: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
- **Customer Filter**: $($CustomerName ? $CustomerName : 'All')
- **Environment Filter**: $($Environment ? $Environment : 'All')
- **Sync Mode**: $($DryRun ? 'DRY RUN' : 'LIVE')
- **Force Sync**: $Force
- **Prune Resources**: $Prune

## Applications Processed
$(foreach ($app in $applications) {
    $customer = $app.metadata.labels.customer
    $environment = $app.metadata.labels.environment
    "- **$($app.metadata.name)** (Customer: $customer, Environment: $environment)"
})

## Results Summary
- **Total Applications**: $($applications.Count)
- **Applications Synced**: $($syncResults.Success)
- **Sync Failures**: $($syncResults.Failed)
- **Skipped**: $($syncResults.Skipped)

## Status
$($DryRun ? '🔍 **DRY RUN COMPLETED**' : '✅ **SYNC COMPLETED**')

---
Generated by ArgoCD Sync Manager
"@

$reportPath = "gitops/sync-reports/sync-report-$(Get-Date -Format 'yyyy-MM-dd-HH-mm').md"
$reportDir = Split-Path $reportPath -Parent

if (-not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

$syncReport | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "📋 Sync report saved: $reportPath" -ForegroundColor Cyan

Write-Host "`n🎯 ArgoCD sync operation completed!" -ForegroundColor Green