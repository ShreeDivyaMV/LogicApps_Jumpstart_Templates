<#
.SYNOPSIS
    Removes all Azure resources created by Deploy-HybridLogicApp-UserAuth.ps1.

.DESCRIPTION
    Deletes (in safe order):
    - Hybrid Logic App
    - Connected Environment
    - Custom Location
    - Container Apps extension
    - Arc-connected cluster
    - AKS cluster
    - SQL Database and Server
    - Storage Account
    - Log Analytics workspace
    - Optionally the Resource Group itself

.PARAMETER SubscriptionId
    Azure subscription ID where resources were deployed.

.PARAMETER ResourceGroup
    Name of the resource group used during deployment.

.PARAMETER DeleteResourceGroup
    If specified, deletes the entire resource group at the end.
    All resources inside it will be permanently removed.

.PARAMETER AksClusterName
    AKS cluster name. Default: logicapp-aks

.PARAMETER ConnectedClusterName
    Arc-connected cluster name. Default: logicapp-arc

.PARAMETER ExtensionName
    Container Apps extension name. Default: logicapps-ext

.PARAMETER CustomLocationName
    Custom location name. Default: logicapp-location

.PARAMETER ConnectedEnvironmentName
    Connected environment name. Default: logicapp-env

.PARAMETER SqlServerName
    SQL Server name. Default: logicappsql

.PARAMETER StorageAccountName
    Storage account name. Default: (auto-detected from resource group)

.PARAMETER WorkspaceName
    Log Analytics workspace name. Default: logicapp-ws

.PARAMETER LogicAppName
    Logic App name. Default: logicapp-hybrid

.EXAMPLE
    .\Teardown-HybridLogicApp.ps1 -SubscriptionId "your-sub-id" -ResourceGroup "logicapp-hybrid-rg"

.EXAMPLE
    .\Teardown-HybridLogicApp.ps1 -SubscriptionId "your-sub-id" -ResourceGroup "logicapp-hybrid-rg" -DeleteResourceGroup
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$true, HelpMessage="Azure subscription ID")]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId,

    [Parameter(Mandatory=$true, HelpMessage="Resource group name")]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroup,

    [Parameter(Mandatory=$false, HelpMessage="Delete the entire resource group")]
    [switch]$DeleteResourceGroup,

    [Parameter(Mandatory=$false)]
    [string]$AksClusterName = "logicapp-aks",

    [Parameter(Mandatory=$false)]
    [string]$ConnectedClusterName = "logicapp-arc",

    [Parameter(Mandatory=$false)]
    [string]$ExtensionName = "logicapps-ext",

    [Parameter(Mandatory=$false)]
    [string]$CustomLocationName = "logicapp-location",

    [Parameter(Mandatory=$false)]
    [string]$ConnectedEnvironmentName = "logicapp-env",

    [Parameter(Mandatory=$false)]
    [string]$SqlServerName = "logicappsql",

    [Parameter(Mandatory=$false)]
    [string]$StorageAccountName = "",

    [Parameter(Mandatory=$false)]
    [string]$WorkspaceName = "logicapp-ws",

    [Parameter(Mandatory=$false)]
    [string]$LogicAppName = "logicapp-hybrid"
)

$ErrorActionPreference = "Continue"

Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "Azure Arc-enabled Hybrid Logic Apps - Teardown" -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "WARNING: This will permanently delete the following resources:" -ForegroundColor Yellow
Write-Host "  Subscription : $SubscriptionId" -ForegroundColor White
Write-Host "  Resource Group: $ResourceGroup" -ForegroundColor White
Write-Host "  Logic App     : $LogicAppName" -ForegroundColor White
Write-Host "  Env           : $ConnectedEnvironmentName" -ForegroundColor White
Write-Host "  Custom Loc    : $CustomLocationName" -ForegroundColor White
Write-Host "  Arc Extension : $ExtensionName" -ForegroundColor White
Write-Host "  Arc Cluster   : $ConnectedClusterName" -ForegroundColor White
Write-Host "  AKS Cluster   : $AksClusterName" -ForegroundColor White
Write-Host "  SQL Server    : $SqlServerName" -ForegroundColor White
Write-Host "  Storage       : $StorageAccountName (or auto-detected)" -ForegroundColor White
Write-Host "  Log Analytics : $WorkspaceName" -ForegroundColor White
if ($DeleteResourceGroup) {
    Write-Host "  Resource Group: $ResourceGroup (WILL BE DELETED)" -ForegroundColor Red
}
Write-Host ""

$confirm = Read-Host "Type 'yes' to proceed"
if ($confirm -ne "yes") {
    Write-Host "Teardown cancelled." -ForegroundColor Yellow
    exit 0
}

# Set subscription
Write-Host "[1] Setting Azure subscription..." -ForegroundColor Yellow
az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to set subscription" -ForegroundColor Red
    exit 1
}
Write-Host "  Done" -ForegroundColor Green

# Auto-detect storage account name if not provided
if ([string]::IsNullOrEmpty($StorageAccountName)) {
    $StorageAccountName = az storage account list `
        --resource-group $ResourceGroup `
        --query "[0].name" -o tsv 2>$null
    if ($StorageAccountName) {
        Write-Host "  Auto-detected storage account: $StorageAccountName" -ForegroundColor Cyan
    }
}

# Delete Logic App
Write-Host "[2] Deleting Logic App: $LogicAppName..." -ForegroundColor Yellow
az logicapp delete `
    --resource-group $ResourceGroup `
    --name $LogicAppName `
    --yes 2>$null
Write-Host "  Done (exit: $LASTEXITCODE)" -ForegroundColor Green

# Delete Connected Environment
Write-Host "[3] Deleting Connected Environment: $ConnectedEnvironmentName..." -ForegroundColor Yellow
az containerapp connected-env delete `
    --resource-group $ResourceGroup `
    --name $ConnectedEnvironmentName `
    --yes 2>$null
Write-Host "  Done (exit: $LASTEXITCODE)" -ForegroundColor Green

# Delete Custom Location
Write-Host "[4] Deleting Custom Location: $CustomLocationName..." -ForegroundColor Yellow
az customlocation delete `
    --resource-group $ResourceGroup `
    --name $CustomLocationName `
    --yes 2>$null
Write-Host "  Done (exit: $LASTEXITCODE)" -ForegroundColor Green

# Delete Container Apps extension
Write-Host "[5] Deleting Container Apps extension: $ExtensionName..." -ForegroundColor Yellow
az k8s-extension delete `
    --cluster-type connectedClusters `
    --cluster-name $ConnectedClusterName `
    --resource-group $ResourceGroup `
    --name $ExtensionName `
    --yes 2>$null
Write-Host "  Done (exit: $LASTEXITCODE)" -ForegroundColor Green

# Disconnect Arc cluster
Write-Host "[6] Disconnecting Arc cluster: $ConnectedClusterName..." -ForegroundColor Yellow
az connectedk8s delete `
    --resource-group $ResourceGroup `
    --name $ConnectedClusterName `
    --yes 2>$null
Write-Host "  Done (exit: $LASTEXITCODE)" -ForegroundColor Green

# Delete AKS cluster
Write-Host "[7] Deleting AKS cluster: $AksClusterName (this may take several minutes)..." -ForegroundColor Yellow
az aks delete `
    --resource-group $ResourceGroup `
    --name $AksClusterName `
    --yes --no-wait 2>$null
Write-Host "  AKS deletion initiated (running in background)" -ForegroundColor Green

# Delete SQL Server (cascades to databases)
Write-Host "[8] Deleting SQL Server: $SqlServerName..." -ForegroundColor Yellow
az sql server delete `
    --resource-group $ResourceGroup `
    --name $SqlServerName `
    --yes 2>$null
Write-Host "  Done (exit: $LASTEXITCODE)" -ForegroundColor Green

# Delete Storage Account
if (-not [string]::IsNullOrEmpty($StorageAccountName)) {
    Write-Host "[9] Deleting Storage Account: $StorageAccountName..." -ForegroundColor Yellow
    az storage account delete `
        --resource-group $ResourceGroup `
        --name $StorageAccountName `
        --yes 2>$null
    Write-Host "  Done (exit: $LASTEXITCODE)" -ForegroundColor Green
}

# Delete Log Analytics workspace
Write-Host "[10] Deleting Log Analytics workspace: $WorkspaceName..." -ForegroundColor Yellow
az monitor log-analytics workspace delete `
    --resource-group $ResourceGroup `
    --workspace-name $WorkspaceName `
    --yes --force 2>$null
Write-Host "  Done (exit: $LASTEXITCODE)" -ForegroundColor Green

# Optionally delete the resource group
if ($DeleteResourceGroup) {
    Write-Host "[11] Deleting resource group: $ResourceGroup..." -ForegroundColor Red
    az group delete `
        --name $ResourceGroup `
        --yes --no-wait
    Write-Host "  Resource group deletion initiated" -ForegroundColor Green
}

Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "Teardown complete." -ForegroundColor Green
Write-Host "Note: AKS deletion runs asynchronously and may take a few minutes." -ForegroundColor Yellow
Write-Host "=====================================================================" -ForegroundColor Cyan
