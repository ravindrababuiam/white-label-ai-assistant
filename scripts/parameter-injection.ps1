# Parameter Injection and Validation Script
# This script handles customer-specific parameter injection and validation

param(
    [Parameter(Mandatory=$true)]
    [string]$CustomerName,
    
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile,
    
    [Parameter(Mandatory=$false)]
    [hashtable]$Parameters = @{},
    
    [Parameter(Mandatory=$false)]
    [switch]$ValidateOnly = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force = $false
)

# Import customer configuration if provided
if ($ConfigFile -and (Test-Path $ConfigFile)) {
    Write-Host "📋 Loading configuration from: $ConfigFile" -ForegroundColor Yellow
    
    $configContent = Get-Content $ConfigFile -Raw
    $config = @{}
    
    # Parse INI-style configuration
    $currentSection = ""
    foreach ($line in ($configContent -split "`n")) {
        $line = $line.Trim()
        if ($line -match '^\[(.+)\]$') {
            $currentSection = $matches[1]
            $config[$currentSection] = @{}
        } elseif ($line -match '^(.+?)\s*=\s*(.+)$' -and $currentSection) {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim().Trim('"')
            $config[$currentSection][$key] = $value
        }
    }
    
    Write-Host "✅ Configuration loaded" -ForegroundColor Green
} else {
    $config = @{}
}

# Define parameter schema with validation rules
$parameterSchema = @{
    'customer_name' = @{
        'required' = $true
        'type' = 'string'
        'pattern' = '^[a-z0-9-]+$'
        'description' = 'Customer name (lowercase, alphanumeric, hyphens only)'
    }
    'aws_region' = @{
        'required' = $true
        'type' = 'string'
        'allowed_values' = @('us-east-1', 'us-west-2', 'eu-west-1', 'ap-southeast-1')
        'description' = 'AWS region for deployment'
    }
    'environment' = @{
        'required' = $true
        'type' = 'string'
        'allowed_values' = @('development', 'staging', 'production')
        'description' = 'Environment type'
    }
    'vpc_cidr' = @{
        'required' = $true
        'type' = 'string'
        'pattern' = '^(\d{1,3}\.){3}\d{1,3}/\d{1,2}$'
        'description' = 'VPC CIDR block'
    }
    'kubernetes_version' = @{
        'required' = $false
        'type' = 'string'
        'allowed_values' = @('1.27', '1.28', '1.29')
        'default' = '1.28'
        'description' = 'Kubernetes version'
    }
    'node_instance_types' = @{
        'required' = $false
        'type' = 'array'
        'default' = @('t3.medium')
        'description' = 'EC2 instance types for worker nodes'
    }
    'enable_gpu_nodes' = @{
        'required' = $false
        'type' = 'boolean'
        'default' = $false
        'description' = 'Enable GPU nodes for Ollama'
    }
    'gpu_instance_types' = @{
        'required' = $false
        'type' = 'array'
        'default' = @('g4dn.xlarge')
        'description' = 'GPU instance types'
    }
    'node_desired_size' = @{
        'required' = $false
        'type' = 'integer'
        'min' = 1
        'max' = 10
        'default' = 2
        'description' = 'Desired number of worker nodes'
    }
    'node_max_size' = @{
        'required' = $false
        'type' = 'integer'
        'min' = 1
        'max' = 20
        'default' = 4
        'description' = 'Maximum number of worker nodes'
    }
    'node_min_size' = @{
        'required' = $false
        'type' = 'integer'
        'min' = 0
        'max' = 5
        'default' = 1
        'description' = 'Minimum number of worker nodes'
    }
    'enable_public_access' = @{
        'required' = $false
        'type' = 'boolean'
        'default' = $true
        'description' = 'Enable public access to EKS API'
    }
    'log_retention_days' = @{
        'required' = $false
        'type' = 'integer'
        'min' = 1
        'max' = 365
        'default' = 30
        'description' = 'CloudWatch log retention in days'
    }
}

# Collect parameters from various sources
$finalParameters = @{}

# 1. Start with defaults
foreach ($paramName in $parameterSchema.Keys) {
    $schema = $parameterSchema[$paramName]
    if ($schema.ContainsKey('default')) {
        $finalParameters[$paramName] = $schema['default']
    }
}

# 2. Override with config file values
if ($config.ContainsKey('Customer')) {
    if ($config['Customer'].ContainsKey('Name')) {
        $finalParameters['customer_name'] = $config['Customer']['Name']
    }
    if ($config['Customer'].ContainsKey('Environment')) {
        $finalParameters['environment'] = $config['Customer']['Environment']
    }
}

if ($config.ContainsKey('AWS')) {
    if ($config['AWS'].ContainsKey('Region')) {
        $finalParameters['aws_region'] = $config['AWS']['Region']
    }
}

if ($config.ContainsKey('Infrastructure')) {
    if ($config['Infrastructure'].ContainsKey('VpcCidr')) {
        $finalParameters['vpc_cidr'] = $config['Infrastructure']['VpcCidr']
    }
    if ($config['Infrastructure'].ContainsKey('EnableGpu')) {
        $finalParameters['enable_gpu_nodes'] = [bool]::Parse($config['Infrastructure']['EnableGpu'])
    }
    if ($config['Infrastructure'].ContainsKey('NodeInstanceTypes')) {
        $finalParameters['node_instance_types'] = $config['Infrastructure']['NodeInstanceTypes'] -split ','
    }
}

# 3. Override with command line parameters
foreach ($paramName in $Parameters.Keys) {
    $finalParameters[$paramName] = $Parameters[$paramName]
}

# 4. Ensure customer name is set
if (-not $finalParameters.ContainsKey('customer_name') -or [string]::IsNullOrEmpty($finalParameters['customer_name'])) {
    $finalParameters['customer_name'] = $CustomerName
}

Write-Host "🔍 Parameter Validation for: $($finalParameters['customer_name'])" -ForegroundColor Green

# Validation function
function Test-Parameter {
    param($Name, $Value, $Schema)
    
    $errors = @()
    
    # Check if required parameter is missing
    if ($Schema['required'] -and ($null -eq $Value -or $Value -eq '')) {
        $errors += "Required parameter '$Name' is missing"
        return $errors
    }
    
    # Skip validation if value is null/empty and not required
    if ($null -eq $Value -or $Value -eq '') {
        return $errors
    }
    
    # Type validation
    switch ($Schema['type']) {
        'string' {
            if ($Value -isnot [string]) {
                $errors += "Parameter '$Name' must be a string"
            }
        }
        'integer' {
            if ($Value -isnot [int]) {
                try {
                    $Value = [int]$Value
                    $finalParameters[$Name] = $Value
                } catch {
                    $errors += "Parameter '$Name' must be an integer"
                }
            }
        }
        'boolean' {
            if ($Value -isnot [bool]) {
                try {
                    $Value = [bool]::Parse($Value)
                    $finalParameters[$Name] = $Value
                } catch {
                    $errors += "Parameter '$Name' must be a boolean"
                }
            }
        }
        'array' {
            if ($Value -isnot [array]) {
                if ($Value -is [string]) {
                    $Value = $Value -split ','
                    $finalParameters[$Name] = $Value
                } else {
                    $errors += "Parameter '$Name' must be an array"
                }
            }
        }
    }
    
    # Pattern validation
    if ($Schema.ContainsKey('pattern') -and $Value -is [string]) {
        if ($Value -notmatch $Schema['pattern']) {
            $errors += "Parameter '$Name' does not match required pattern: $($Schema['pattern'])"
        }
    }
    
    # Allowed values validation
    if ($Schema.ContainsKey('allowed_values')) {
        if ($Value -notin $Schema['allowed_values']) {
            $errors += "Parameter '$Name' must be one of: $($Schema['allowed_values'] -join ', ')"
        }
    }
    
    # Range validation for integers
    if ($Schema['type'] -eq 'integer' -and $Value -is [int]) {
        if ($Schema.ContainsKey('min') -and $Value -lt $Schema['min']) {
            $errors += "Parameter '$Name' must be at least $($Schema['min'])"
        }
        if ($Schema.ContainsKey('max') -and $Value -gt $Schema['max']) {
            $errors += "Parameter '$Name' must be at most $($Schema['max'])"
        }
    }
    
    return $errors
}

# Validate all parameters
$validationErrors = @()
$validationWarnings = @()

foreach ($paramName in $parameterSchema.Keys) {
    $schema = $parameterSchema[$paramName]
    $value = $finalParameters[$paramName]
    
    $errors = Test-Parameter -Name $paramName -Value $value -Schema $schema
    $validationErrors += $errors
    
    if ($errors.Count -eq 0) {
        Write-Host "  ✅ $paramName`: $value" -ForegroundColor Green
    } else {
        Write-Host "  ❌ $paramName`: $($errors -join ', ')" -ForegroundColor Red
    }
}

# Additional business logic validations
Write-Host "`n🔧 Business Logic Validation..." -ForegroundColor Yellow

# GPU validation
if ($finalParameters['enable_gpu_nodes'] -and $finalParameters['environment'] -eq 'development') {
    $validationWarnings += "GPU nodes enabled in development environment - this may increase costs"
}

# Node size validation
if ($finalParameters['node_min_size'] -gt $finalParameters['node_desired_size']) {
    $validationErrors += "node_min_size cannot be greater than node_desired_size"
}

if ($finalParameters['node_desired_size'] -gt $finalParameters['node_max_size']) {
    $validationErrors += "node_desired_size cannot be greater than node_max_size"
}

# VPC CIDR validation
$vpcCidr = $finalParameters['vpc_cidr']
if ($vpcCidr -match '^(\d+)\.(\d+)\.(\d+)\.(\d+)/(\d+)$') {
    $cidrBits = [int]$matches[5]
    if ($cidrBits -gt 24) {
        $validationWarnings += "VPC CIDR /$cidrBits may be too small for multi-AZ deployment"
    }
}

# Display validation results
Write-Host "`n📊 Validation Summary:" -ForegroundColor Cyan

if ($validationErrors.Count -eq 0) {
    Write-Host "✅ All validations passed!" -ForegroundColor Green
} else {
    Write-Host "❌ Validation failed with $($validationErrors.Count) errors:" -ForegroundColor Red
    foreach ($error in $validationErrors) {
        Write-Host "  • $error" -ForegroundColor Red
    }
}

if ($validationWarnings.Count -gt 0) {
    Write-Host "⚠️ Warnings:" -ForegroundColor Yellow
    foreach ($warning in $validationWarnings) {
        Write-Host "  • $warning" -ForegroundColor Yellow
    }
}

# Exit if validation only
if ($ValidateOnly) {
    if ($validationErrors.Count -eq 0) {
        Write-Host "🎯 Parameters are valid for deployment" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "❌ Fix validation errors before deployment" -ForegroundColor Red
        exit 1
    }
}

# Stop if there are validation errors and not forced
if ($validationErrors.Count -gt 0 -and -not $Force) {
    Write-Host "❌ Cannot proceed with validation errors. Use -Force to override." -ForegroundColor Red
    exit 1
}

# Generate terraform.tfvars content
Write-Host "`n📝 Generating Terraform variables..." -ForegroundColor Yellow

$tfvarsContent = @"
# Terraform variables for customer: $($finalParameters['customer_name'])
# Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# Validation: $($validationErrors.Count -eq 0 ? 'PASSED' : 'FAILED')

# Basic Configuration
customer_name = "$($finalParameters['customer_name'])"
aws_region    = "$($finalParameters['aws_region'])"
environment   = "$($finalParameters['environment'])"

# Network Configuration
vpc_cidr = "$($finalParameters['vpc_cidr'])"
availability_zones = ["$($finalParameters['aws_region'])a", "$($finalParameters['aws_region'])b"]

# EKS Configuration
kubernetes_version = "$($finalParameters['kubernetes_version'])"
node_capacity_type = "ON_DEMAND"
node_instance_types = [$(($finalParameters['node_instance_types'] | ForEach-Object { '"' + $_ + '"' }) -join ', ')]
node_desired_size = $($finalParameters['node_desired_size'])
node_max_size = $($finalParameters['node_max_size'])
node_min_size = $($finalParameters['node_min_size'])
node_disk_size = 50

# GPU Configuration
enable_gpu_nodes = $($finalParameters['enable_gpu_nodes'].ToString().ToLower())
gpu_instance_types = [$(($finalParameters['gpu_instance_types'] | ForEach-Object { '"' + $_ + '"' }) -join ', ')]
gpu_node_desired_size = $($finalParameters['enable_gpu_nodes'] ? 1 : 0)
gpu_node_max_size = $($finalParameters['enable_gpu_nodes'] ? 2 : 0)
gpu_node_min_size = 0
gpu_node_disk_size = 100

# Access Configuration
enable_public_access = $($finalParameters['enable_public_access'].ToString().ToLower())
public_access_cidrs = ["0.0.0.0/0"]
enable_node_ssh_access = false
node_ssh_key_name = ""

# Logging
log_retention_days = $($finalParameters['log_retention_days'])

# Tags
additional_tags = {
  "Customer" = "$($finalParameters['customer_name'])"
  "Environment" = "$($finalParameters['environment'])"
  "CreatedBy" = "parameter-injection-automation"
  "CreatedDate" = "$(Get-Date -Format "yyyy-MM-dd")"
  "ValidationStatus" = "$($validationErrors.Count -eq 0 ? 'PASSED' : 'FAILED')"
}
"@

# Save to customer directory
$customerDir = "terraform/environments/$($finalParameters['customer_name'])"
if (-not (Test-Path $customerDir)) {
    New-Item -ItemType Directory -Path $customerDir -Force | Out-Null
}

$tfvarsPath = "$customerDir/terraform.tfvars"
$tfvarsContent | Out-File -FilePath $tfvarsPath -Encoding UTF8

Write-Host "✅ Terraform variables saved to: $tfvarsPath" -ForegroundColor Green

# Generate parameter summary
$parameterSummary = @"
# Parameter Summary for $($finalParameters['customer_name'])

## Validation Results
- **Status**: $($validationErrors.Count -eq 0 ? 'PASSED' : 'FAILED')
- **Errors**: $($validationErrors.Count)
- **Warnings**: $($validationWarnings.Count)

## Final Parameters
$(foreach ($param in $finalParameters.GetEnumerator() | Sort-Object Name) {
    "- **$($param.Key)**: $($param.Value)"
})

## Generated Files
- Terraform variables: $tfvarsPath

---
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@

$summaryPath = "$customerDir/parameter-summary.md"
$parameterSummary | Out-File -FilePath $summaryPath -Encoding UTF8

Write-Host "📋 Parameter summary saved to: $summaryPath" -ForegroundColor Cyan

if ($validationErrors.Count -eq 0) {
    Write-Host "🎯 Parameters validated and injected successfully!" -ForegroundColor Green
    Write-Host "Ready for Terraform deployment" -ForegroundColor Green
} else {
    Write-Host "⚠️ Parameters injected with validation errors" -ForegroundColor Yellow
    Write-Host "Review and fix errors before deployment" -ForegroundColor Yellow
}