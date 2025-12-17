# Azure Arc-enabled Hybrid Logic Apps on AKS

This solution deploys Azure Logic Apps in a hybrid configuration using Azure Arc-enabled Kubernetes, running on Azure Kubernetes Service (AKS) with SQL Server backend and SMB file share storage.

## Architecture Overview

The deployment creates:
- **Azure Kubernetes Service (AKS)** - Managed Kubernetes cluster
- **Azure Arc-enabled Kubernetes** - Connection layer to Azure Arc services
- **Azure Container Apps Extension** - Enables Logic Apps hosting on Kubernetes
- **Azure SQL Database** - Stores workflow state and metadata
- **Azure Storage Account** - SMB file share for workflow artifacts
- **Custom Location** - Azure location abstraction for Arc-enabled services
- **Connected Environment** - Container Apps environment on Arc-enabled cluster
- **Hybrid Logic App** - Standard Logic App running on Kubernetes

## Prerequisites

Before deploying, ensure you have:

### Tools & Software
- **Azure CLI** version 2.40.0 or later ([Install](https://docs.microsoft.com/cli/azure/install-azure-cli))
- **kubectl** version 1.28.0 or later - Will be installed automatically by the script if not present
- **Helm** version 3.0.0 or later - Will be installed automatically by the script if not present
- **PowerShell** 5.1 or later (Windows) or PowerShell Core 7+ (cross-platform)

### Azure Requirements
- **Active Azure subscription**
- **Azure CLI extensions**: Will be installed automatically by script
  - `connectedk8s`
  - `k8s-extension`
  - `customlocation`
  - `containerapp`

> **Note**: The deployment script automatically checks for and installs kubectl and Helm if they are not found on your system. You only need to ensure Azure CLI and PowerShell are installed manually.

### Permissions
- Contributor access to the Azure subscription
- Ability to register Azure resource providers

## Quick Start

### Automated Deployment with User Authentication

The `Deploy-HybridLogicApp-UserAuth.ps1` script provides a fully automated deployment using Azure CLI with interactive user authentication.

1. **Clone or download this repository**
   ```powershell
   git clone ttps://github.com/ShreeDivyaMV/azure_arc.git
   ```

2. **Run the deployment script**:
   ```powershell
   cd ARM
   .\Deploy-HybridLogicApp-UserAuth.ps1 `
       -SubscriptionId "your-subscription-id" `
       -ResourceGroup "logicapp-hybrid-rg" `
       -Location "westeurope" `
       -SqlAdminPassword (ConvertTo-SecureString "YourStrongPassword123!" -AsPlainText -Force)
   ```

3. **Monitor deployment** - The script will:
   - Automatically install kubectl and Helm if not present
   - Prompt for Azure login (browser-based authentication)
   - Create all resources automatically (30-45 minutes)
   - Display progress for each of the 21 deployment steps


#### Optional Parameters

You can customize the deployment with additional parameters:

```powershell
.\Deploy-HybridLogicApp-UserAuth.ps1 `
    -SubscriptionId "2ba690bf-a85f-4cbc-b4cb-3bfead7e2f97" `
    -ResourceGroup "my-logicapp-rg" `
    -Location "westeurope" `
    -SqlAdminPassword (ConvertTo-SecureString "MyP@ssw0rd123!" -AsPlainText -Force) `
    -KubernetesVersion "1.32.9" `
    -SqlAdminUsername "sqladmin" `
    -SqlDatabaseName "LogicAppDB" `
    -FileShareName "logicapp-artifacts" `
    -AksClusterName "my-aks-cluster" `
    -ConnectedClusterName "my-arc-cluster" `
    -ExtensionName "logicapps-ext" `
    -Namespace "logicapps-ns" `
    -CustomLocationName "my-custom-location" `
    -ConnectedEnvironmentName "my-connected-env" `
    -SqlServerName "mylogicappsql" `
    -StorageAccountName "mylogicappsa" `
    -WorkspaceName "my-workspace" `
    -LogicAppName "my-logicapp"

> **Note**: The storage mount name is automatically generated as `{LogicAppName}-smb` and does not need to be specified.
```

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `logicAppName` | Logic App name | - | Yes |
| `customLocationName` | Custom location name | - | Yes |
| `connectedEnvironmentName` | Connected environment name | - | Yes |
| `storageAccountName` | Storage account name | - | Yes |
| `fileShareName` | SMB file share name | - | Yes |
| `storageAccountKey` | Storage account key | - | Yes |
| `sqlConnectionString` | SQL connection string | - | Yes |
| `minReplicas` | Minimum replicas | 1 | No |
| `maxReplicas` | Maximum replicas | 3 | No |
| `cpu` | CPU allocation | 0.5 | No |
| `memory` | Memory allocation | 1Gi | No |

## Deployment Components

### 1. Azure Kubernetes Service (AKS)
- **VM Size**: Standard_D4s_v3
- **Node Count**: 3 (autoscaling 1-6)
- **Kubernetes Version**: 1.30.0
- **Add-ons**: Monitoring (Log Analytics)

### 2. Azure SQL Database
- **Tier**: Standard S0
- **Purpose**: Stores workflow run history and state
- **Firewall**: Azure services allowed
- **Connection**: Encrypted with TLS 1.2

### 3. Storage Account (SMB File Share)
- **Type**: StorageV2 (Standard LRS)
- **Protocol**: SMB 3.0
- **Quota**: 5 TB
- **Purpose**: Stores workflow definitions and artifacts
- **Mount**: Via SMB CSI driver in Kubernetes

### 4. Azure Arc Connection
- **Purpose**: Connects AKS to Azure Arc services
- **Extensions**: Container Apps (Microsoft.App.Environment)
- **Namespace**: Configurable (default: logicapps-ns)
- **Features**: 
  - KEDA autoscaling enabled
  - Logic Apps scaler with replica count of 1
  - Functions server API enabled
  - Functions proxy API configuration
  - Log Analytics integration for application logs
  - Azure Load Balancer annotations

### 5. Container Apps Connected Environment
- **Type**: Arc-enabled
- **Ingress**: External (HTTPS)
- **Scaling**: KEDA-based autoscaling
- **Monitoring**: Log Analytics integration

### 6. Hybrid Logic App
- **Type**: Standard (Container Apps)
- **Image**: mcr.microsoft.com/azurelogicapps/logicapps-base:validation
- **Kind**: workflowapp
- **Storage**: SMB volume mount for /home/site/wwwroot
- **State**: SQL Database backend






### Monitoring

1. **View logs in Log Analytics**:
   ```bash
   az monitor log-analytics query \
     --workspace <workspace-id> \
     --analytics-query "ContainerAppConsoleLogs_CL | where ContainerAppName_s == '<logic-app-name>' | order by TimeGenerated desc | take 100"
   ```

2. **Check pod status**:
   ```bash
   kubectl get pods -n logicapps-aca-ns
   kubectl logs -n logicapps-aca-ns <pod-name>
   ```

## Testing

We provide comprehensive testing scripts:

### Pre-Deployment Tests
```powershell
cd ARM/artifacts
.\TestDeployment.ps1 -TestMode PreDeployment
```

Validates:
- Azure CLI, kubectl, Helm installations
- ARM template syntax
- Parameters configuration
- Azure login status

### Post-Deployment Tests
```powershell
.\TestDeployment.ps1 -TestMode PostDeployment -ResourceGroup <rg-name>
```

Validates:
- All Azure resources created
- Arc connection established
- Extension installed
- Pods running
- SQL and Storage accessible

See [TESTING.md](TESTING.md) for detailed testing guide.

## Troubleshooting

### Common Issues

1. **Arc connection fails**
   
   - Check network connectivity from AKS
   - Ensure resource providers are registered

2. **Extension installation pending**
   - Wait 5-10 minutes (normal for first-time installation)
   - Check: `az k8s-extension show --cluster-type connectedClusters --cluster-name <name> --resource-group <rg> --name <extension-name>`

3. **Logic App not accessible**
   - Verify custom location created
   - Check pods running: `kubectl get pods -n logicapps-aca-ns`
   - Review logs: `kubectl logs -n logicapps-aca-ns <pod-name>`

4. **SQL connection fails**
   - Verify firewall rules allow Azure services
   - Test connection: `Test-NetConnection -ComputerName <server>.database.windows.net -Port 1433`
   - Check connection string in Logic App configuration

### Get Support

- **GitHub Issues**: [microsoft/azure_arc](https://github.com/microsoft/azure_arc/issues)
- **Documentation**: [Hybrid Logic Apps](https://learn.microsoft.com/azure/logic-apps/set-up-standard-workflows-hybrid-deployment-requirements)
- **Azure Support**: [Create support request](https://portal.azure.com/#create/Microsoft.Support)


## Cleanup

To delete all resources:

```bash
# Delete resource group (WARNING: Deletes ALL resources)
az group delete --name <resource-group-name> --yes --no-wait

# Or selectively delete resources
az aks delete --resource-group <rg> --name <aks-cluster> --yes
az connectedk8s delete --resource-group <rg> --name <arc-cluster>
az sql server delete --resource-group <rg> --name <sql-server>
az storage account delete --resource-group <rg> --name <storage-account>
```

## Additional Resources

- [Azure Arc-enabled Kubernetes](https://learn.microsoft.com/azure/azure-arc/kubernetes/overview)
- [Azure Container Apps on Arc](https://learn.microsoft.com/azure/container-apps/azure-arc-overview)
- [Logic Apps Standard](https://learn.microsoft.com/azure/logic-apps/single-tenant-overview-compare)
- [Hybrid Logic Apps Requirements](https://learn.microsoft.com/azure/logic-apps/set-up-standard-workflows-hybrid-deployment-requirements)




