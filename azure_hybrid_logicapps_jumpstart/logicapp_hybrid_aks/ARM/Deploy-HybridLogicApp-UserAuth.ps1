<#
.SYNOPSIS
    Deploys Hybrid Logic Apps infrastructure on Azure Arc-enabled Kubernetes.

.DESCRIPTION
    This script automates the complete deployment of:
    - AKS cluster with Arc enablement
    - Azure SQL Server and Database
    - Storage Account with SMB file share
    - Container Apps connected environment
    - Hybrid Logic App

.PARAMETER SubscriptionId
    Azure subscription ID where resources will be deployed.

.PARAMETER ResourceGroup
    Name of the resource group to create or use.

.PARAMETER Location
    Azure region for deployment (e.g., westeurope, eastus).

.PARAMETER SqlAdminPassword
    Password for SQL Server admin account (must meet complexity requirements).

.PARAMETER KubernetesVersion
    Optional. Kubernetes version for AKS cluster. Default is 1.32.9.

.PARAMETER SqlAdminUsername
    Optional. SQL Server admin username. Default is 'sqladmin'.

.PARAMETER SqlDatabaseName
    Optional. SQL Database name. Default is 'LogicAppDB'.

.PARAMETER FileShareName
    Optional. Storage file share name. Default is 'logicapp-artifacts'.

.EXAMPLE
    .\Deploy-HybridLogicApp-UserAuth.ps1 -SubscriptionId "your-sub-id" -ResourceGroup "my-rg" -Location "westeurope" -SqlAdminPassword (ConvertTo-SecureString "MyP@ssw0rd123!" -AsPlainText -Force)

.EXAMPLE
    .\Deploy-HybridLogicApp-UserAuth.ps1 -SubscriptionId "your-sub-id" -ResourceGroup "my-rg" -Location "eastus" -SqlAdminPassword (ConvertTo-SecureString "MyP@ssw0rd123!" -AsPlainText -Force) -KubernetesVersion "1.31.0"

.EXAMPLE
    # Full example with all optional parameters
    .\Deploy-HybridLogicApp-UserAuth.ps1 `
        -SubscriptionId "2ba690bf-a85f-4cbc-b4cb-3bfead7e2f97" `
        -ResourceGroup "my-logicapp-rg" `
        -Location "westeurope" `
        -SqlAdminPassword (ConvertTo-SecureString "MyP@ssw0rd123!" -AsPlainText -Force) `
        -KubernetesVersion "1.32.9" `
        -SqlAdminUsername "sqladmin" `
        -SqlDatabaseName "LogicAppDB" `
        -FileShareName "logicapp-artifacts" `
        -AksClusterName "my-aks-77501" `
        -ConnectedClusterName "my-arc-77501" `
        -ExtensionName "my-logicapps-ext" `
        -Namespace "my-logicapps-ns" `
        -CustomLocationName "my-location-77501" `
        -ConnectedEnvironmentName "my-env-77501" `
        -SqlServerName "mylogicappsql77501" `
        -StorageAccountName "mylogicappsa77501" `
        -WorkspaceName "my-workspace-77501" `
        -LogicAppName "my-logicapp-77501"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, HelpMessage="Azure subscription ID")]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId,

    [Parameter(Mandatory=$true, HelpMessage="Resource group name")]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroup,

    [Parameter(Mandatory=$true, HelpMessage="Azure region (e.g., westeurope, eastus)")]
    [ValidateNotNullOrEmpty()]
    [string]$Location,

    [Parameter(Mandatory=$true, HelpMessage="SQL Server admin password")]
    [ValidateNotNullOrEmpty()]
    [SecureString]$SqlAdminPassword,

    [Parameter(Mandatory=$false, HelpMessage="Kubernetes version for AKS")]
    [ValidateNotNullOrEmpty()]
    [string]$KubernetesVersion = "1.32.9",

    [Parameter(Mandatory=$false, HelpMessage="SQL Server admin username")]
    [ValidateNotNullOrEmpty()]
    [string]$SqlAdminUsername = "sqladmin",

    [Parameter(Mandatory=$false, HelpMessage="SQL Database name")]
    [ValidateNotNullOrEmpty()]
    [string]$SqlDatabaseName = "LogicAppDB",

    [Parameter(Mandatory=$false, HelpMessage="Storage file share name")]
    [ValidateNotNullOrEmpty()]
    [string]$FileShareName = "logicapp-artifacts",

    [Parameter(Mandatory=$false, HelpMessage="AKS cluster name")]
    [ValidateNotNullOrEmpty()]
    [string]$AksClusterName = "logicapp-aks" ,

    [Parameter(Mandatory=$false, HelpMessage="Arc-enabled cluster name")]
    [ValidateNotNullOrEmpty()]
    [string]$ConnectedClusterName = "logicapp-arc" ,

    [Parameter(Mandatory=$false, HelpMessage="Container Apps extension name")]
    [ValidateNotNullOrEmpty()]
    [string]$ExtensionName = "logicapps-ext",

    [Parameter(Mandatory=$false, HelpMessage="Kubernetes namespace for Logic Apps")]
    [ValidateNotNullOrEmpty()]
    [string]$Namespace = "logicapps-ns",

    [Parameter(Mandatory=$false, HelpMessage="Custom location name")]
    [ValidateNotNullOrEmpty()]
    [string]$CustomLocationName = "logicapp-location" ,

    [Parameter(Mandatory=$false, HelpMessage="Connected environment name")]
    [ValidateNotNullOrEmpty()]
    [string]$ConnectedEnvironmentName = "logicapp-env",

    [Parameter(Mandatory=$false, HelpMessage="SQL Server name")]
    [ValidateNotNullOrEmpty()]
    [string]$SqlServerName = "logicappsql" ,

    [Parameter(Mandatory=$false, HelpMessage="Storage account name")]
    [ValidateNotNullOrEmpty()]
    [string]$StorageAccountName = "logicappsa",

    [Parameter(Mandatory=$false, HelpMessage="Log Analytics workspace name")]
    [ValidateNotNullOrEmpty()]
    [string]$WorkspaceName = "logicapp-ws" ,

    [Parameter(Mandatory=$false, HelpMessage="Logic App name")]
    [ValidateNotNullOrEmpty()]
    [string]$LogicAppName = "logicapp-hybrid"
)

# Convert SecureString password to plain text for use in connection strings
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SqlAdminPassword)
$sqlAdminPasswordPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

# Trim whitespace from all string parameters to prevent issues
$SubscriptionId = $SubscriptionId.Trim()
$ResourceGroup = $ResourceGroup.Trim()
$Location = $Location.Trim()
$KubernetesVersion = $KubernetesVersion.Trim()
$SqlAdminUsername = $SqlAdminUsername.Trim()
$SqlDatabaseName = $SqlDatabaseName.Trim()
$FileShareName = $FileShareName.Trim()
$AksClusterName = $AksClusterName.Trim()
$ConnectedClusterName = $ConnectedClusterName.Trim()
$ExtensionName = $ExtensionName.Trim()
$Namespace = $Namespace.Trim()
$CustomLocationName = $CustomLocationName.Trim()
$ConnectedEnvironmentName = $ConnectedEnvironmentName.Trim()
$SqlServerName = $SqlServerName.Trim()
$StorageAccountName = $StorageAccountName.Trim()
$WorkspaceName = $WorkspaceName.Trim()
$LogicAppName = $LogicAppName.Trim()

# Generate storage mount name based on Logic App name
$StorageMountName = "$LogicAppName-smb"

# ============================================================================
# SCRIPT EXECUTION - Do not modify below this line
# ============================================================================

$ErrorActionPreference = "Continue"
Start-Transcript -Path ".\HybridLogicAppSetup-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "Azure Arc-enabled Hybrid Logic Apps - Complete Deployment" -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Subscription: $SubscriptionId" -ForegroundColor White
Write-Host "  Resource Group: $ResourceGroup" -ForegroundColor White
Write-Host "  Location: $Location" -ForegroundColor White
Write-Host "  Kubernetes Version: $KubernetesVersion" -ForegroundColor White
Write-Host ""

# Check and install prerequisites
Write-Host "[1/21] Checking and installing prerequisites..." -ForegroundColor Yellow

# Check kubectl
$kubectlInstalled = $false
try {
    $null = kubectl version --client 2>&1
    if ($LASTEXITCODE -eq 0) {
        $kubectlVersion = kubectl version --client --short 2>&1 | Select-String "Client Version"
        Write-Host "  kubectl is already installed: $kubectlVersion" -ForegroundColor Green
        $kubectlInstalled = $true
    }
} catch {
    Write-Host "  kubectl not found" -ForegroundColor Yellow
}

if (-not $kubectlInstalled) {
    Write-Host "  Installing kubectl..." -ForegroundColor Cyan
    $kubectlUrl = "https://dl.k8s.io/release/v1.32.0/bin/windows/amd64/kubectl.exe"
    $kubectlPath = "$env:TEMP\kubectl.exe"
    Invoke-WebRequest -Uri $kubectlUrl -OutFile $kubectlPath -UseBasicParsing
    
    $installDir = "$env:ProgramFiles\kubectl"
    if (-not (Test-Path $installDir)) {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    }
    Move-Item -Path $kubectlPath -Destination "$installDir\kubectl.exe" -Force
    
    # Add to PATH if not already there
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($currentPath -notlike "*$installDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$currentPath;$installDir", "Machine")
        $env:Path = "$env:Path;$installDir"
    }
    Write-Host "  kubectl installed successfully" -ForegroundColor Green
}

# Check Helm
$helmInstalled = $false
try {
    $null = helm version --short 2>&1
    if ($LASTEXITCODE -eq 0) {
        $helmVersion = helm version --short 2>&1
        Write-Host "  Helm is already installed: $helmVersion" -ForegroundColor Green
        $helmInstalled = $true
    }
} catch {
    Write-Host "  Helm not found" -ForegroundColor Yellow
}

if (-not $helmInstalled) {
    Write-Host "  Installing Helm..." -ForegroundColor Cyan
    $helmUrl = "https://get.helm.sh/helm-v3.16.2-windows-amd64.zip"
    $helmZip = "$env:TEMP\helm.zip"
    $helmExtract = "$env:TEMP\helm"
    
    Invoke-WebRequest -Uri $helmUrl -OutFile $helmZip -UseBasicParsing
    Expand-Archive -Path $helmZip -DestinationPath $helmExtract -Force
    
    $installDir = "$env:ProgramFiles\helm"
    if (-not (Test-Path $installDir)) {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    }
    Move-Item -Path "$helmExtract\windows-amd64\helm.exe" -Destination "$installDir\helm.exe" -Force
    
    # Add to PATH if not already there
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($currentPath -notlike "*$installDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$currentPath;$installDir", "Machine")
        $env:Path = "$env:Path;$installDir"
    }
    
    # Cleanup
    Remove-Item -Path $helmZip -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $helmExtract -Recurse -Force -ErrorAction SilentlyContinue
    
    Write-Host "  Helm installed successfully" -ForegroundColor Green
}

Write-Host "  Prerequisites check complete" -ForegroundColor Green

# Login to Azure
Write-Host "[2/21] Logging into Azure..." -ForegroundColor Yellow
az login
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to login to Azure" -ForegroundColor Red
    Stop-Transcript
    exit 1
}
Write-Host "  Login successful" -ForegroundColor Green

# Set subscription
Write-Host "[3/21] Setting Azure subscription..." -ForegroundColor Yellow
az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to set subscription" -ForegroundColor Red
    Stop-Transcript
    exit 1
}
Write-Host "  Subscription set successfully" -ForegroundColor Green

# Check if resource group exists, create if not
Write-Host "[4/21] Checking resource group..." -ForegroundColor Yellow
$rgExists = az group exists --name $ResourceGroup
if ($rgExists -eq "true") {
    Write-Host "  Resource group '$ResourceGroup' already exists" -ForegroundColor Cyan
} else {
    Write-Host "  Creating resource group '$ResourceGroup' in '$Location'..." -ForegroundColor Cyan
    az group create --name $ResourceGroup --location $Location
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Resource group created successfully!" -ForegroundColor Green
    } else {
        Write-Host "  ERROR: Failed to create resource group" -ForegroundColor Red
        Stop-Transcript
        exit 1
    }
}

# Register required resource providers
Write-Host "[5/21] Registering Azure resource providers..." -ForegroundColor Yellow
$providers = @(
    "Microsoft.ContainerService",
    "Microsoft.Kubernetes",
    "Microsoft.KubernetesConfiguration",
    "Microsoft.ExtendedLocation",
    "Microsoft.App",
    "Microsoft.OperationalInsights",
    "Microsoft.Web",
    "Microsoft.Sql",
    "Microsoft.Storage"
)

foreach ($provider in $providers) {
    Write-Host "  Registering $provider..." -ForegroundColor Cyan
    az provider register --namespace $provider --wait
}
Write-Host "  All providers registered" -ForegroundColor Green

# Install Azure CLI extensions
Write-Host "[6/21] Installing Azure CLI extensions..." -ForegroundColor Yellow
az extension add --name connectedk8s --upgrade --yes 2>&1 | Out-Null
az extension add --name k8s-extension --upgrade --yes 2>&1 | Out-Null
az extension add --name customlocation --upgrade --yes 2>&1 | Out-Null
az extension add --name containerapp --upgrade --yes 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to install Azure CLI extensions" -ForegroundColor Red
    Stop-Transcript
    exit 1
}
Write-Host "  Extensions installed" -ForegroundColor Green

# Create Log Analytics workspace
Write-Host "[7/21] Creating Log Analytics workspace..." -ForegroundColor Yellow
$workspaceExists = az monitor log-analytics workspace show `
    --resource-group $ResourceGroup `
    --workspace-name $WorkspaceName `
    --query name -o tsv 2>$null

if ($workspaceExists) {
    Write-Host "  Log Analytics workspace already exists: $WorkspaceName" -ForegroundColor Cyan
} else {
    az monitor log-analytics workspace create `
        --resource-group $ResourceGroup `
        --workspace-name $WorkspaceName `
        --location $Location | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to create Log Analytics workspace" -ForegroundColor Red
        Stop-Transcript
        exit 1
    }
    Write-Host "  Log Analytics workspace created: $WorkspaceName" -ForegroundColor Green
}

# Create AKS cluster
Write-Host "[8/21] Creating AKS cluster (this may take 10-15 minutes)..." -ForegroundColor Yellow
$aksExists = az aks show `
    --resource-group $ResourceGroup `
    --name $AksClusterName `
    --query name -o tsv 2>$null

if ($aksExists) {
    Write-Host "  AKS cluster already exists: $AksClusterName" -ForegroundColor Cyan
} else {
    az aks create `
        --resource-group $ResourceGroup `
        --name $AksClusterName `
        --kubernetes-version $KubernetesVersion `
        --node-count 3 `
        --node-vm-size Standard_D4s_v3 `
    --enable-managed-identity `
    --enable-cluster-autoscaler `
    --min-count 1 `
    --max-count 6 `
    --location $Location `
    --no-wait

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to initiate AKS cluster creation" -ForegroundColor Red
        Stop-Transcript
        exit 1
    }
    Write-Host "  AKS cluster creation initiated..." -ForegroundColor Cyan
    Write-Host "  Waiting for cluster to be ready..." -ForegroundColor Yellow
    az aks wait --resource-group $ResourceGroup --name $AksClusterName --created --interval 30 --timeout 1200
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: AKS cluster creation failed or timed out" -ForegroundColor Red
        Stop-Transcript
        exit 1
    }
    Write-Host "  AKS cluster created successfully: $AksClusterName" -ForegroundColor Green
}

# Get AKS credentials
Write-Host "[9/21] Configuring kubectl access to AKS cluster..." -ForegroundColor Yellow
az aks get-credentials --resource-group $ResourceGroup --name $AksClusterName --admin --overwrite-existing
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to get AKS credentials" -ForegroundColor Red
    Stop-Transcript
    exit 1
}
kubectl get nodes
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to access AKS cluster with kubectl" -ForegroundColor Red
    Stop-Transcript
    exit 1
}
Write-Host "  kubectl configured" -ForegroundColor Green

# Create SQL Server and Database
Write-Host "[10/21] Creating Azure SQL Server and Database..." -ForegroundColor Yellow
$sqlServerExists = az sql server show `
    --resource-group $ResourceGroup `
    --name $SqlServerName `
    --query name -o tsv 2>$null

if ($sqlServerExists) {
    Write-Host "  SQL Server already exists: $SqlServerName" -ForegroundColor Cyan
} else {
    az sql server create `
        --resource-group $ResourceGroup `
        --name $SqlServerName `
        --location $Location `
        --admin-user $SqlAdminUsername `
        --admin-password $sqlAdminPasswordPlain | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to create SQL Server" -ForegroundColor Red
        Stop-Transcript
        exit 1
    }
    Write-Host "  SQL Server created: $SqlServerName" -ForegroundColor Green
}

az sql server firewall-rule create `
    --resource-group $ResourceGroup `
    --server $SqlServerName `
    --name AllowAzureServices `
    --start-ip-address 0.0.0.0 `
    --end-ip-address 0.0.0.0 2>$null | Out-Null

$sqlDbExists = az sql db show `
    --resource-group $ResourceGroup `
    --server $SqlServerName `
    --name $SqlDatabaseName `
    --query name -o tsv 2>$null

if ($sqlDbExists) {
    Write-Host "  SQL Database already exists: $SqlDatabaseName" -ForegroundColor Cyan
} else {
    az sql db create `
        --resource-group $ResourceGroup `
        --server $SqlServerName `
        --name $SqlDatabaseName `
        --service-objective S0 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to create SQL Database" -ForegroundColor Red
        Stop-Transcript
        exit 1
    }
    Write-Host "  SQL Database created: $SqlDatabaseName" -ForegroundColor Green
}

# Create Storage Account
Write-Host "[11/21] Creating Storage Account with SMB file share..." -ForegroundColor Yellow
$storageExists = az storage account show `
    --resource-group $ResourceGroup `
    --name $StorageAccountName `
    --query name -o tsv 2>$null

if ($storageExists) {
    Write-Host "  Storage Account already exists: $StorageAccountName" -ForegroundColor Cyan
} else {
    az storage account create `
        --resource-group $ResourceGroup `
        --name $StorageAccountName `
        --location $Location `
        --sku Standard_LRS `
        --kind StorageV2 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to create Storage Account" -ForegroundColor Red
        Stop-Transcript
        exit 1
    }
    Write-Host "  Storage Account created: $StorageAccountName" -ForegroundColor Green
}

$storageAccountKey = az storage account keys list `
    --resource-group $ResourceGroup `
    --account-name $StorageAccountName `
    --query "[0].value" -o tsv
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to get Storage Account key" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# Check if file share exists
$fileShareExists = az storage share exists `
    --name $FileShareName `
    --account-name $StorageAccountName `
    --account-key $storageAccountKey `
    --query exists -o tsv 2>$null

if ($fileShareExists -eq "true") {
    Write-Host "  File share already exists: $FileShareName" -ForegroundColor Cyan
} else {
    az storage share create `
        --name $FileShareName `
        --account-name $StorageAccountName `
        --account-key $storageAccountKey `
        --quota 5120 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  File share created: $FileShareName" -ForegroundColor Green
    } else {
        Write-Host "ERROR: Failed to create file share" -ForegroundColor Red
        Stop-Transcript
        exit 1
    }
}

# Check if directory exists in file share
$directoryExists = az storage directory exists `
    --name $LogicAppName `
    --share-name $FileShareName `
    --account-name $StorageAccountName `
    --account-key $storageAccountKey `
    --query exists -o tsv 2>$null

if ($directoryExists -eq "true") {
    Write-Host "  Directory already exists in file share: $LogicAppName" -ForegroundColor Cyan
} else {
    az storage directory create `
        --name $LogicAppName `
        --share-name $FileShareName `
        --account-name $StorageAccountName `
        --account-key $storageAccountKey 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Directory created in file share: $LogicAppName" -ForegroundColor Green
    } else {
        Write-Host "WARNING: Failed to create directory in file share (may already exist)" -ForegroundColor Yellow
    }
}

Write-Host "  File share configured: $FileShareName" -ForegroundColor Green

# Install SMB CSI driver
Write-Host "[12/21] Installing SMB CSI driver..." -ForegroundColor Yellow
$smbDriverExists = helm list -n kube-system | Select-String "csi-driver-smb"
if ($smbDriverExists) {
    Write-Host "  SMB CSI driver already installed" -ForegroundColor Cyan
} else {
    helm repo add csi-driver-smb https://raw.githubusercontent.com/kubernetes-csi/csi-driver-smb/master/charts 2>&1 | Out-Null
    helm repo update 2>&1 | Out-Null
    helm install csi-driver-smb csi-driver-smb/csi-driver-smb --namespace kube-system --version v1.15.0 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to install SMB CSI driver" -ForegroundColor Red
        Stop-Transcript
        exit 1
    }
    Write-Host "  SMB CSI driver installed" -ForegroundColor Green
}
Start-Sleep -Seconds 10
kubectl get csidriver

# Connect cluster to Azure Arc
Write-Host "[13/21] Connecting AKS cluster to Azure Arc (5-10 minutes)..." -ForegroundColor Yellow
$arcConnected = az connectedk8s show `
    --resource-group $ResourceGroup `
    --name $ConnectedClusterName `
    --query name -o tsv 2>$null

if ($arcConnected) {
    Write-Host "  AKS cluster already connected to Azure Arc: $ConnectedClusterName" -ForegroundColor Cyan
} else {
    az connectedk8s connect `
        --resource-group $ResourceGroup `
        --name $ConnectedClusterName `
        --location $Location
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to connect cluster to Azure Arc" -ForegroundColor Red
        Stop-Transcript
        exit 1
    }
    Write-Host "  Arc connection completed: $ConnectedClusterName" -ForegroundColor Green
}

# Get Log Analytics workspace credentials
Write-Host "[14/21] Getting Log Analytics workspace credentials..." -ForegroundColor Yellow
$workspaceId = az monitor log-analytics workspace show `
    --resource-group $ResourceGroup `
    --workspace-name $WorkspaceName `
    --query customerId -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($workspaceId)) {
    Write-Host "ERROR: Failed to get Log Analytics workspace ID" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

$workspaceKey = az monitor log-analytics workspace get-shared-keys `
    --resource-group $ResourceGroup `
    --workspace-name $WorkspaceName `
    --query primarySharedKey -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($workspaceKey)) {
    Write-Host "ERROR: Failed to get Log Analytics workspace key" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

$workspaceIdEncoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($workspaceId))
$workspaceKeyEncoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($workspaceKey))
Write-Host "  Credentials retrieved" -ForegroundColor Green

# Install Container Apps extension
Write-Host "[15/21] Installing Azure Container Apps extension (5-10 minutes)..." -ForegroundColor Yellow
$extensionExists = az k8s-extension show `
    --cluster-type connectedClusters `
    --cluster-name $ConnectedClusterName `
    --resource-group $ResourceGroup `
    --name $ExtensionName `
    --query name -o tsv 2>$null

if ($extensionExists) {
    Write-Host "  Container Apps extension already installed: $ExtensionName" -ForegroundColor Cyan
} else {
    az k8s-extension create `
        --resource-group $ResourceGroup `
        --name $ExtensionName `
        --cluster-type connectedClusters `
        --cluster-name $ConnectedClusterName `
        --extension-type 'Microsoft.App.Environment' `
        --release-train stable `
        --auto-upgrade-minor-version true `
        --scope cluster `
        --release-namespace $Namespace `
        --configuration-settings "Microsoft.CustomLocation.ServiceAccount=default" `
        --configuration-settings "appsNamespace=$Namespace" `
        --configuration-settings "keda.enabled=true" `
        --configuration-settings "keda.logicAppsScaler.enabled=true" `
        --configuration-settings "keda.logicAppsScaler.replicaCount=1" `
        --configuration-settings "containerAppController.api.functionsServerEnabled=true" `
        --configuration-settings "envoy.externalServiceAzureILB=false" `
        --configuration-settings "functionsProxyApiConfig.enabled=true" `
        --configuration-settings "clusterName=$ConnectedEnvironmentName" `
        --configuration-settings "envoy.annotations.service.beta.kubernetes.io/azure-load-balancer-resource-group=$ResourceGroup" `
        --configuration-settings "logProcessor.appLogs.destination=log-analytics" `
        --configuration-protected-settings "logProcessor.appLogs.logAnalyticsConfig.customerId=$workspaceIdEncoded" `
        --configuration-protected-settings "logProcessor.appLogs.logAnalyticsConfig.sharedKey=$workspaceKeyEncoded" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to create Container Apps extension" -ForegroundColor Red
        Stop-Transcript
        exit 1
    }
    Write-Host "  Extension created, waiting for installation..." -ForegroundColor Cyan
}

$extensionId = az k8s-extension show `
    --cluster-type connectedClusters `
    --cluster-name $ConnectedClusterName `
    --resource-group $ResourceGroup `
    --name $ExtensionName `
    --query id -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($extensionId)) {
    Write-Host "ERROR: Failed to get extension ID" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

Write-Host "  Waiting for extension to be ready..." -ForegroundColor Yellow
az resource wait `
    --ids $extensionId `
    --custom "properties.provisioningState!='Pending'" `
    --api-version "2020-07-01-preview" `
    --timeout 600
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Extension installation failed or timed out" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

Write-Host "  Extension installed: $ExtensionName" -ForegroundColor Green

# Create custom location
Write-Host "[16/21] Creating custom location..." -ForegroundColor Yellow
$customLocationExists = az customlocation show `
    --resource-group $ResourceGroup `
    --name $CustomLocationName `
    --query name -o tsv 2>$null

if ($customLocationExists) {
    Write-Host "  Custom location already exists: $CustomLocationName" -ForegroundColor Cyan
    $customLocationId = az customlocation show `
        --resource-group $ResourceGroup `
        --name $CustomLocationName `
        --query id -o tsv
} else {
    $connectedClusterId = az connectedk8s show `
    --resource-group $ResourceGroup `
    --name $ConnectedClusterName `
    --query id -o tsv

az customlocation create `
        --resource-group $ResourceGroup `
        --name $CustomLocationName `
        --host-resource-id $connectedClusterId `
        --namespace $Namespace `
        --cluster-extension-ids $extensionId `
        --location $Location | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to create custom location" -ForegroundColor Red
        Stop-Transcript
        exit 1
    }

    

    Start-Sleep -Seconds 15

    $customLocationId = az customlocation show `
        --resource-group $ResourceGroup `
        --name $CustomLocationName `
        --query id -o tsv
    Write-Host "  Custom location created: $CustomLocationName" -ForegroundColor Green
}

if ([string]::IsNullOrEmpty($customLocationId)) {
    Write-Host "ERROR: Failed to get custom location ID" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# Create Container Apps connected environment
Write-Host "[17/21] Creating Container Apps connected environment..." -ForegroundColor Yellow
$connectedEnvExists = az containerapp connected-env show `
    --resource-group $ResourceGroup `
    --name $ConnectedEnvironmentName `
    --query name -o tsv 2>$null

if ($connectedEnvExists) {
    Write-Host "  Connected environment already exists: $ConnectedEnvironmentName" -ForegroundColor Cyan
} else {
    az containerapp connected-env create `
        --resource-group $ResourceGroup `
        --name $ConnectedEnvironmentName `
        --custom-location $customLocationId `
        --location $Location | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to create connected environment" -ForegroundColor Red
        Stop-Transcript
        exit 1
    }
    Write-Host "  Connected environment created: $ConnectedEnvironmentName" -ForegroundColor Green
}

$connectedEnvId = az containerapp connected-env show `
    --resource-group $ResourceGroup `
    --name $ConnectedEnvironmentName `
    --query id -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($connectedEnvId)) {
    Write-Host "ERROR: Failed to get connected environment ID" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# Create SMB storage mount on Connected Environment
Write-Host "[18/21] Creating SMB storage mount on Connected Environment..." -ForegroundColor Yellow

$storageMountTemplateFile = ".\storage-mount-template.json"
if (-not (Test-Path $storageMountTemplateFile)) {
    Write-Host "ERROR: Storage mount template file not found: $storageMountTemplateFile" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

az deployment group create `
    --resource-group $ResourceGroup `
    --template-file $storageMountTemplateFile `
    --parameters connectedEnvironmentName="$ConnectedEnvironmentName" `
                 storageMountName="$StorageMountName" `
                 storageAccountName="$StorageAccountName" `
                 storageAccountKey="$storageAccountKey" `
                 fileShareName="$FileShareName" `
                 logicAppName="$LogicAppName" `
    --name "storage-mount-$(Get-Date -Format 'yyyyMMdd-HHmmss')" | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to create SMB storage mount" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

Write-Host "  SMB storage mount created: $StorageMountName" -ForegroundColor Green

# Create Logic App using ARM template
Write-Host "[19/21] Creating Hybrid Logic App using ARM template..." -ForegroundColor Yellow

$logicAppExists = az containerapp show `
    --name $LogicAppName `
    --resource-group $ResourceGroup `
    --query name -o tsv 2>$null

if ($logicAppExists) {
    Write-Host "  Logic App already exists: $LogicAppName" -ForegroundColor Cyan
} else {
    $sqlConnectionString = "Server=tcp:$SqlServerName.database.windows.net,1433;Initial Catalog=$SqlDatabaseName;User ID=$SqlAdminUsername;Password=$sqlAdminPasswordPlain;Encrypt=True;"

    $logicAppTemplateFile = ".\logicapp-template.json"
    if (-not (Test-Path $logicAppTemplateFile)) {
        Write-Host "ERROR: Logic App template file not found: $logicAppTemplateFile" -ForegroundColor Red
        Stop-Transcript
        exit 1
    }

    az deployment group create `
        --resource-group $ResourceGroup `
        --template-file $logicAppTemplateFile `
        --parameters logicAppName="$LogicAppName" `
                     customLocationName="$CustomLocationName" `
                     connectedEnvironmentName="$ConnectedEnvironmentName" `
                     storageMountName="$StorageMountName" `
                     sqlConnectionString="$sqlConnectionString" `
                     location="$Location" `
        --name "logicapp-deployment-$(Get-Date -Format 'yyyyMMddHHmmss')"

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Logic App created: $LogicAppName" -ForegroundColor Green
    } else {
        Write-Host "ERROR: Failed to create Logic App" -ForegroundColor Red
        Write-Host "Check the deployment logs for details" -ForegroundColor Yellow
        Stop-Transcript
        exit 1
    }
}

# Verify Logic App deployment
Write-Host "[20/21] Verifying Logic App deployment..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

$logicAppStatus = az containerapp show `
    --name $LogicAppName `
    --resource-group $ResourceGroup `
    --query "{Name:name, Status:properties.provisioningState, Running:properties.runningStatus, Image:properties.template.containers[0].image}" `
    -o json 2>$null | ConvertFrom-Json

if ($logicAppStatus) {
    Write-Host "  Logic App Status:" -ForegroundColor Cyan
    Write-Host "    Name: $($logicAppStatus.Name)" -ForegroundColor White
    Write-Host "    Provisioning State: $($logicAppStatus.Status)" -ForegroundColor White
    Write-Host "    Running Status: $($logicAppStatus.Running)" -ForegroundColor White
    Write-Host "    Container Image: $($logicAppStatus.Image)" -ForegroundColor White
    
    if ($logicAppStatus.Status -ne "Succeeded") {
        Write-Host "WARNING: Logic App provisioning state is not 'Succeeded'" -ForegroundColor Yellow
    }
} else {
    Write-Host "WARNING: Could not retrieve Logic App status - check Azure Portal" -ForegroundColor Yellow
}

# Final setup message
Write-Host "[21/21] Deployment complete - Finalizing..." -ForegroundColor Yellow

Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host "DEPLOYMENT COMPLETE!" -ForegroundColor Green
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Resources Created:" -ForegroundColor Cyan
Write-Host "  Resource Group: $ResourceGroup" -ForegroundColor White
Write-Host "  AKS Cluster: $AksClusterName" -ForegroundColor White
Write-Host "  Arc-enabled Cluster: $ConnectedClusterName" -ForegroundColor White
Write-Host "  Custom Location: $CustomLocationName" -ForegroundColor White
Write-Host "  Connected Environment: $ConnectedEnvironmentName" -ForegroundColor White
Write-Host "  Storage Mount: $StorageMountName" -ForegroundColor White
Write-Host "  SQL Server: $SqlServerName.database.windows.net" -ForegroundColor White
Write-Host "  SQL Database: $SqlDatabaseName" -ForegroundColor White
Write-Host "  Storage Account: $StorageAccountName" -ForegroundColor White
Write-Host "  Logic App: $LogicAppName" -ForegroundColor White
Write-Host ""
Write-Host "Portal URL:" -ForegroundColor Cyan
Write-Host "  https://portal.azure.com/#resource/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.App/containerapps/$LogicAppName" -ForegroundColor Yellow
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Access Logic App in Azure Portal (URL above)" -ForegroundColor White
Write-Host "  2. Create workflows in the Logic App designer" -ForegroundColor White
Write-Host "  3. Use the pre-configured SQL connection for data operations" -ForegroundColor White
Write-Host ""

Stop-Transcript

Write-Host "Log file saved to current directory" -ForegroundColor Green

