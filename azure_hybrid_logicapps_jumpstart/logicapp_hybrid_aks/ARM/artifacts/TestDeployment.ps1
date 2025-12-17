# Test and Validation Script for Hybrid Logic Apps Deployment
# This script validates the deployment without actually deploying resources

param(
    [Parameter(Mandatory=$false)]
    [string]$TestMode = "PreDeployment",  # PreDeployment, PostDeployment, FullValidation
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "",
    
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = ""
)

Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "Hybrid Logic Apps Deployment - Test & Validation Script" -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Test Mode: $TestMode" -ForegroundColor Yellow
Write-Host ""

# Test results tracking
$testResults = @()

function Add-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message
    )
    
    $result = @{
        Test = $TestName
        Passed = $Passed
        Message = $Message
        Timestamp = Get-Date
    }
    
    $script:testResults += $result
    
    if ($Passed) {
        Write-Host "✓ PASS: $TestName" -ForegroundColor Green
        if ($Message) { Write-Host "  $Message" -ForegroundColor Gray }
    } else {
        Write-Host "✗ FAIL: $TestName" -ForegroundColor Red
        if ($Message) { Write-Host "  $Message" -ForegroundColor Yellow }
    }
}

# ============================================================================
# PRE-DEPLOYMENT TESTS
# ============================================================================

if ($TestMode -eq "PreDeployment" -or $TestMode -eq "FullValidation") {
    Write-Host "Running Pre-Deployment Tests..." -ForegroundColor Yellow
    Write-Host ""
    
    # Test 1: Check Azure CLI installation
    Write-Host "[1/12] Testing Azure CLI..." -ForegroundColor Cyan
    try {
        $azVersion = az version --output json 2>$null | ConvertFrom-Json
        if ($azVersion.'azure-cli') {
            Add-TestResult "Azure CLI Installation" $true "Version: $($azVersion.'azure-cli')"
        } else {
            Add-TestResult "Azure CLI Installation" $false "Azure CLI not found"
        }
    } catch {
        Add-TestResult "Azure CLI Installation" $false "Error: $_"
    }
    
    # Test 2: Check kubectl installation
    Write-Host "[2/12] Testing kubectl..." -ForegroundColor Cyan
    try {
        $kubectlVersion = kubectl version --client=true --output=json 2>$null | ConvertFrom-Json
        if ($kubectlVersion) {
            Add-TestResult "kubectl Installation" $true "Version: $($kubectlVersion.clientVersion.gitVersion)"
        } else {
            Add-TestResult "kubectl Installation" $false "kubectl not found"
        }
    } catch {
        Add-TestResult "kubectl Installation" $false "Error: $_"
    }
    
    # Test 3: Check Helm installation
    Write-Host "[3/12] Testing Helm..." -ForegroundColor Cyan
    try {
        $helmVersion = helm version --short 2>$null
        if ($helmVersion) {
            Add-TestResult "Helm Installation" $true "Version: $helmVersion"
        } else {
            Add-TestResult "Helm Installation" $false "Helm not found"
        }
    } catch {
        Add-TestResult "Helm Installation" $false "Error: $_"
    }
    
    # Test 4: Check PowerShell version
    Write-Host "[4/12] Testing PowerShell..." -ForegroundColor Cyan
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -ge 5) {
        Add-TestResult "PowerShell Version" $true "Version: $($psVersion.Major).$($psVersion.Minor)"
    } else {
        Add-TestResult "PowerShell Version" $false "PowerShell 5.1 or later required"
    }
    
    # Test 5: Check Azure CLI extensions
    Write-Host "[5/12] Testing Azure CLI Extensions..." -ForegroundColor Cyan
    $requiredExtensions = @('connectedk8s', 'k8s-extension', 'customlocation', 'containerapp')
    $installedExtensions = az extension list --output json | ConvertFrom-Json
    
    foreach ($ext in $requiredExtensions) {
        $found = $installedExtensions | Where-Object { $_.name -eq $ext }
        if ($found) {
            Add-TestResult "Azure CLI Extension: $ext" $true "Version: $($found.version)"
        } else {
            Add-TestResult "Azure CLI Extension: $ext" $false "Not installed (will be installed during deployment)"
        }
    }
    
    # Test 6: Validate ARM template syntax
    Write-Host "[6/12] Testing ARM Template Syntax..." -ForegroundColor Cyan
    $templatePath = Join-Path $PSScriptRoot "..\azuredeploy.json"
    if (Test-Path $templatePath) {
        try {
            $template = Get-Content $templatePath -Raw | ConvertFrom-Json
            if ($template.'$schema' -and $template.resources) {
                Add-TestResult "ARM Template Syntax" $true "Template is valid JSON"
            } else {
                Add-TestResult "ARM Template Syntax" $false "Template structure invalid"
            }
        } catch {
            Add-TestResult "ARM Template Syntax" $false "Error: $_"
        }
    } else {
        Add-TestResult "ARM Template Syntax" $false "Template file not found"
    }
    
    # Test 7: Validate Logic App template syntax
    Write-Host "[7/12] Testing Logic App Template Syntax..." -ForegroundColor Cyan
    $logicAppTemplatePath = Join-Path $PSScriptRoot "..\logicapp.json"
    if (Test-Path $logicAppTemplatePath) {
        try {
            $template = Get-Content $logicAppTemplatePath -Raw | ConvertFrom-Json
            if ($template.'$schema' -and $template.resources) {
                Add-TestResult "Logic App Template Syntax" $true "Template is valid JSON"
            } else {
                Add-TestResult "Logic App Template Syntax" $false "Template structure invalid"
            }
        } catch {
            Add-TestResult "Logic App Template Syntax" $false "Error: $_"
        }
    } else {
        Add-TestResult "Logic App Template Syntax" $false "Template file not found"
    }
    
    # Test 8: Validate parameters file
    Write-Host "[8/12] Testing Parameters File..." -ForegroundColor Cyan
    $parametersPath = Join-Path $PSScriptRoot "..\azuredeploy.parameters.json"
    if (Test-Path $parametersPath) {
        try {
            $params = Get-Content $parametersPath -Raw | ConvertFrom-Json
            if ($params.parameters) {
                $requiredParams = @('spnClientId', 'spnClientSecret', 'spnTenantId', 'sqlAdminPassword')
                $missingParams = @()
                
                foreach ($param in $requiredParams) {
                    if (-not $params.parameters.$param -or $params.parameters.$param.value -like "*<your-*") {
                        $missingParams += $param
                    }
                }
                
                if ($missingParams.Count -eq 0) {
                    Add-TestResult "Parameters File" $true "All required parameters configured"
                } else {
                    Add-TestResult "Parameters File" $false "Missing/placeholder parameters: $($missingParams -join ', ')"
                }
            } else {
                Add-TestResult "Parameters File" $false "Invalid parameters structure"
            }
        } catch {
            Add-TestResult "Parameters File" $false "Error: $_"
        }
    } else {
        Add-TestResult "Parameters File" $false "Parameters file not found"
    }
    
    # Test 9: Check if logged into Azure
    Write-Host "[9/12] Testing Azure Login..." -ForegroundColor Cyan
    try {
        $account = az account show 2>$null | ConvertFrom-Json
        if ($account) {
            Add-TestResult "Azure Login Status" $true "Logged in as: $($account.user.name)"
        } else {
            Add-TestResult "Azure Login Status" $false "Not logged into Azure"
        }
    } catch {
        Add-TestResult "Azure Login Status" $false "Not logged into Azure"
    }
    
    # Test 10: Validate sample workflow
    Write-Host "[10/12] Testing Sample Workflow..." -ForegroundColor Cyan
    $workflowPath = Join-Path $PSScriptRoot "sample-workflow.json"
    if (Test-Path $workflowPath) {
        try {
            $workflow = Get-Content $workflowPath -Raw | ConvertFrom-Json
            if ($workflow.definition -and $workflow.kind) {
                Add-TestResult "Sample Workflow" $true "Workflow definition is valid"
            } else {
                Add-TestResult "Sample Workflow" $false "Invalid workflow structure"
            }
        } catch {
            Add-TestResult "Sample Workflow" $false "Error: $_"
        }
    } else {
        Add-TestResult "Sample Workflow" $false "Sample workflow file not found"
    }
    
    # Test 11: Check deployment script
    Write-Host "[11/12] Testing Deployment Script..." -ForegroundColor Cyan
    $deployScriptPath = Join-Path $PSScriptRoot "DeployHybridLogicApps.ps1"
    if (Test-Path $deployScriptPath) {
        try {
            $scriptContent = Get-Content $deployScriptPath -Raw
            if ($scriptContent -match "az login" -and $scriptContent -match "az aks create") {
                Add-TestResult "Deployment Script" $true "Script contains expected commands"
            } else {
                Add-TestResult "Deployment Script" $false "Script may be incomplete"
            }
        } catch {
            Add-TestResult "Deployment Script" $false "Error: $_"
        }
    } else {
        Add-TestResult "Deployment Script" $false "Deployment script not found"
    }
    
    # Test 12: Check README documentation
    Write-Host "[12/12] Testing Documentation..." -ForegroundColor Cyan
    $readmePath = Join-Path $PSScriptRoot "..\..\README.md"
    if (Test-Path $readmePath) {
        $readmeContent = Get-Content $readmePath -Raw
        if ($readmeContent -match "Quick Start" -and $readmeContent -match "Prerequisites") {
            Add-TestResult "Documentation" $true "README.md is complete"
        } else {
            Add-TestResult "Documentation" $false "README.md may be incomplete"
        }
    } else {
        Add-TestResult "Documentation" $false "README.md not found"
    }
}

# ============================================================================
# POST-DEPLOYMENT TESTS
# ============================================================================

if ($TestMode -eq "PostDeployment" -or $TestMode -eq "FullValidation") {
    
    if (-not $ResourceGroup) {
        Write-Host "Resource Group name required for post-deployment tests!" -ForegroundColor Red
        Write-Host "Usage: .\TestDeployment.ps1 -TestMode PostDeployment -ResourceGroup <rg-name>" -ForegroundColor Yellow
        return
    }
    
    Write-Host ""
    Write-Host "Running Post-Deployment Tests..." -ForegroundColor Yellow
    Write-Host "Resource Group: $ResourceGroup" -ForegroundColor Cyan
    Write-Host ""
    
    # Test 1: Check AKS cluster
    Write-Host "[1/10] Testing AKS Cluster..." -ForegroundColor Cyan
    try {
        $aksClusters = az aks list --resource-group $ResourceGroup --output json | ConvertFrom-Json
        if ($aksClusters.Count -gt 0) {
            $cluster = $aksClusters[0]
            Add-TestResult "AKS Cluster" $true "Cluster: $($cluster.name), Status: $($cluster.provisioningState)"
        } else {
            Add-TestResult "AKS Cluster" $false "No AKS cluster found"
        }
    } catch {
        Add-TestResult "AKS Cluster" $false "Error: $_"
    }
    
    # Test 2: Check Arc-enabled cluster
    Write-Host "[2/10] Testing Arc-enabled Cluster..." -ForegroundColor Cyan
    try {
        $arcClusters = az connectedk8s list --resource-group $ResourceGroup --output json | ConvertFrom-Json
        if ($arcClusters.Count -gt 0) {
            $cluster = $arcClusters[0]
            Add-TestResult "Arc-enabled Cluster" $true "Cluster: $($cluster.name), Status: $($cluster.connectivityStatus)"
        } else {
            Add-TestResult "Arc-enabled Cluster" $false "No Arc-enabled cluster found"
        }
    } catch {
        Add-TestResult "Arc-enabled Cluster" $false "Error: $_"
    }
    
    # Test 3: Check Container Apps extension
    Write-Host "[3/10] Testing Container Apps Extension..." -ForegroundColor Cyan
    try {
        if ($arcClusters.Count -gt 0) {
            $extensions = az k8s-extension list --cluster-type connectedClusters --cluster-name $arcClusters[0].name --resource-group $ResourceGroup --output json | ConvertFrom-Json
            $caExtension = $extensions | Where-Object { $_.extensionType -eq 'Microsoft.App.Environment' }
            if ($caExtension) {
                Add-TestResult "Container Apps Extension" $true "Extension: $($caExtension.name), Status: $($caExtension.provisioningState)"
            } else {
                Add-TestResult "Container Apps Extension" $false "Extension not found"
            }
        }
    } catch {
        Add-TestResult "Container Apps Extension" $false "Error: $_"
    }
    
    # Test 4: Check Custom Location
    Write-Host "[4/10] Testing Custom Location..." -ForegroundColor Cyan
    try {
        $locations = az customlocation list --resource-group $ResourceGroup --output json | ConvertFrom-Json
        if ($locations.Count -gt 0) {
            $location = $locations[0]
            Add-TestResult "Custom Location" $true "Location: $($location.name), Status: $($location.provisioningState)"
        } else {
            Add-TestResult "Custom Location" $false "No custom location found"
        }
    } catch {
        Add-TestResult "Custom Location" $false "Error: $_"
    }
    
    # Test 5: Check Connected Environment
    Write-Host "[5/10] Testing Connected Environment..." -ForegroundColor Cyan
    try {
        $envs = az containerapp connected-env list --resource-group $ResourceGroup --output json | ConvertFrom-Json
        if ($envs.Count -gt 0) {
            $env = $envs[0]
            Add-TestResult "Connected Environment" $true "Environment: $($env.name), Status: $($env.provisioningState)"
        } else {
            Add-TestResult "Connected Environment" $false "No connected environment found"
        }
    } catch {
        Add-TestResult "Connected Environment" $false "Error: $_"
    }
    
    # Test 6: Check SQL Server
    Write-Host "[6/10] Testing SQL Server..." -ForegroundColor Cyan
    try {
        $sqlServers = az sql server list --resource-group $ResourceGroup --output json | ConvertFrom-Json
        if ($sqlServers.Count -gt 0) {
            $server = $sqlServers[0]
            Add-TestResult "SQL Server" $true "Server: $($server.name), State: $($server.state)"
        } else {
            Add-TestResult "SQL Server" $false "No SQL server found"
        }
    } catch {
        Add-TestResult "SQL Server" $false "Error: $_"
    }
    
    # Test 7: Check SQL Database
    Write-Host "[7/10] Testing SQL Database..." -ForegroundColor Cyan
    try {
        if ($sqlServers.Count -gt 0) {
            $databases = az sql db list --resource-group $ResourceGroup --server $sqlServers[0].name --output json | ConvertFrom-Json
            $userDb = $databases | Where-Object { $_.name -ne 'master' }
            if ($userDb) {
                Add-TestResult "SQL Database" $true "Database: $($userDb.name), Status: $($userDb.status)"
            } else {
                Add-TestResult "SQL Database" $false "No user database found"
            }
        }
    } catch {
        Add-TestResult "SQL Database" $false "Error: $_"
    }
    
    # Test 8: Check Storage Account
    Write-Host "[8/10] Testing Storage Account..." -ForegroundColor Cyan
    try {
        $storageAccounts = az storage account list --resource-group $ResourceGroup --output json | ConvertFrom-Json
        if ($storageAccounts.Count -gt 0) {
            $storage = $storageAccounts[0]
            Add-TestResult "Storage Account" $true "Account: $($storage.name), Status: $($storage.statusOfPrimary)"
        } else {
            Add-TestResult "Storage Account" $false "No storage account found"
        }
    } catch {
        Add-TestResult "Storage Account" $false "Error: $_"
    }
    
    # Test 9: Check Kubernetes pods
    Write-Host "[9/10] Testing Kubernetes Pods..." -ForegroundColor Cyan
    try {
        $pods = kubectl get pods -n logicapps-aca-ns --output json 2>$null | ConvertFrom-Json
        if ($pods.items.Count -gt 0) {
            $runningPods = ($pods.items | Where-Object { $_.status.phase -eq 'Running' }).Count
            Add-TestResult "Kubernetes Pods" $true "Running pods: $runningPods / $($pods.items.Count)"
        } else {
            Add-TestResult "Kubernetes Pods" $false "No pods found in logicapps-aca-ns namespace"
        }
    } catch {
        Add-TestResult "Kubernetes Pods" $false "Error: $_"
    }
    
    # Test 10: Check Log Analytics Workspace
    Write-Host "[10/10] Testing Log Analytics Workspace..." -ForegroundColor Cyan
    try {
        $workspaces = az monitor log-analytics workspace list --resource-group $ResourceGroup --output json | ConvertFrom-Json
        if ($workspaces.Count -gt 0) {
            $workspace = $workspaces[0]
            Add-TestResult "Log Analytics Workspace" $true "Workspace: $($workspace.name), State: $($workspace.provisioningState)"
        } else {
            Add-TestResult "Log Analytics Workspace" $false "No workspace found"
        }
    } catch {
        Add-TestResult "Log Analytics Workspace" $false "Error: $_"
    }
}

# ============================================================================
# TEST SUMMARY
# ============================================================================

Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host ""

$passed = ($testResults | Where-Object { $_.Passed -eq $true }).Count
$failed = ($testResults | Where-Object { $_.Passed -eq $false }).Count
$total = $testResults.Count

Write-Host "Total Tests: $total" -ForegroundColor White
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($failed -gt 0) {
    Write-Host "Failed Tests:" -ForegroundColor Red
    $testResults | Where-Object { $_.Passed -eq $false } | ForEach-Object {
        Write-Host "  ✗ $($_.Test)" -ForegroundColor Red
        Write-Host "    $($_.Message)" -ForegroundColor Yellow
    }
    Write-Host ""
}

# Calculate pass rate
$passRate = [math]::Round(($passed / $total) * 100, 2)
Write-Host "Pass Rate: $passRate%" -ForegroundColor $(if ($passRate -ge 80) { "Green" } elseif ($passRate -ge 60) { "Yellow" } else { "Red" })
Write-Host ""

# Export results
$resultsFile = "TestResults_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
$testResults | ConvertTo-Json -Depth 10 | Out-File $resultsFile
Write-Host "Test results exported to: $resultsFile" -ForegroundColor Cyan

Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host ""

# Recommendations
if ($TestMode -eq "PreDeployment" -or $TestMode -eq "FullValidation") {
    if ($failed -eq 0) {
        Write-Host "✓ All pre-deployment tests passed! Ready to deploy." -ForegroundColor Green
    } else {
        Write-Host "⚠ Some tests failed. Please fix the issues before deployment." -ForegroundColor Yellow
    }
}

if ($TestMode -eq "PostDeployment" -or $TestMode -eq "FullValidation") {
    if ($failed -eq 0) {
        Write-Host "✓ All post-deployment tests passed! Deployment successful." -ForegroundColor Green
    } else {
        Write-Host "⚠ Some tests failed. Please review the deployment." -ForegroundColor Yellow
    }
}
