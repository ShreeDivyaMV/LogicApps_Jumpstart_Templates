````markdown
# Testing Guide for Hybrid Logic Apps Deployment

## Test Summary

✅ **Prerequisites Validated:**
- Azure CLI: v2.77.0 - Installed and working
- kubectl: v1.34.1 - Installed and working
- Helm: v3.18.6 - Installed and working
- PowerShell: Available for scripting
- Required Azure CLI Extensions: connectedk8s, k8s-extension, customlocation, containerapp

## Quick Test Commands

### 1. Pre-Deployment Tests

Run these tests BEFORE deploying to ensure your environment is ready:

```powershell
# Test script is available at:
.\TestDeployment.ps1 -TestMode PreDeployment

# Manual pre-deployment checks:

# 1. Check Azure CLI
az version

# 2. Check if logged into Azure
az account show

# 3. Check kubectl
kubectl version --client

# 4. Check Helm
helm version --short

# 5. Validate ARM template syntax (requires resource group)
az deployment group validate `
  --resource-group <test-rg> `
  --template-file ..\azuredeploy.json `
  --parameters ..\azuredeploy.parameters.json

# 6. Validate Logic App template
az deployment group validate `
  --resource-group <test-rg> `
  --template-file ..\logicapp.json `
  --parameters ..\logicapp.parameters.json
```

### 2. Dry-Run Deployment Test

Test the deployment without creating resources:

```powershell
# Create a test resource group
$testRG = "logicapp-test-rg-$(Get-Random -Maximum 9999)"
az group create --name $testRG --location eastus

# Validate the template deployment (no actual resources created)
az deployment group validate `
  --resource-group $testRG `
  --template-file ..\azuredeploy.json `
  --parameters ..\azuredeploy.parameters.json

# What-If analysis (shows what would be created)
az deployment group what-if `
  --resource-group $testRG `
  --template-file ..\azuredeploy.json `
  --parameters ..\azuredeploy.parameters.json

# Clean up test resource group
az group delete --name $testRG --yes --no-wait
```

### 3. Post-Deployment Tests

Run these tests AFTER deploying to verify everything works:

```powershell
# Test script
.\TestDeployment.ps1 -TestMode PostDeployment -ResourceGroup <your-rg-name>

# Manual post-deployment checks:

# 1. Check AKS cluster
az aks list --resource-group <rg-name> --output table

# 2. Get AKS credentials and test connection
az aks get-credentials --resource-group <rg-name> --name <aks-cluster-name> --admin --overwrite-existing
kubectl get nodes
kubectl get pods --all-namespaces

# 3. Check Arc-enabled cluster
az connectedk8s list --resource-group <rg-name> --output table
az connectedk8s show --resource-group <rg-name> --name <cluster-name>

# 4. Check Container Apps extension
az k8s-extension list `
  --cluster-type connectedClusters `
  --cluster-name <cluster-name> `
  --resource-group <rg-name> `
  --output table

# 5. Check Custom Location
az customlocation list --resource-group <rg-name> --output table

# 6. Check Connected Environment
az containerapp connected-env list --resource-group <rg-name> --output table

# 7. Check SQL Server
az sql server list --resource-group <rg-name> --output table
az sql db list --resource-group <rg-name> --server <sql-server-name> --output table

# 8. Check Storage Account
az storage account list --resource-group <rg-name> --output table

# 9. Check Log Analytics Workspace
az monitor log-analytics workspace list --resource-group <rg-name> --output table

# 10. Check Kubernetes pods in logic apps namespace
kubectl get pods -n logicapps-aca-ns
kubectl get services -n logicapps-aca-ns
kubectl get deployments -n logicapps-aca-ns
```

### 4. Logic App Connectivity Tests

Test the deployed Logic App:

```powershell
# Get Logic App details
az containerapp list --resource-group <rg-name> --output table

# Get Logic App FQDN
$logicAppFqdn = az containerapp show `
  --resource-group <rg-name> `
  --name <logic-app-name> `
  --query properties.configuration.ingress.fqdn `
  --output tsv

Write-Host "Logic App URL: https://$logicAppFqdn"

# Test HTTP trigger (if using sample workflow)
Invoke-RestMethod -Uri "https://$logicAppFqdn/api/workflows/sample/triggers/manual/invoke" `
  -Method Post `
  -Body (@{ name = "Test" } | ConvertTo-Json) `
  -ContentType "application/json"
```

### 5. Component Health Checks

```powershell
# Check AKS cluster health
az aks show --resource-group <rg-name> --name <aks-cluster-name> --query "powerState.code"

# Check Arc connection status
az connectedk8s show --resource-group <rg-name> --name <cluster-name> --query "connectivityStatus"

# Check SQL Server connectivity
$sqlServer = "<sql-server-name>.database.windows.net"
$database = "LogicAppDB"
Test-NetConnection -ComputerName $sqlServer -Port 1433

# Check Storage Account accessibility
az storage account show-connection-string `
  --resource-group <rg-name> `
  --name <storage-account-name>

# Check SMB CSI driver
kubectl get csidriver
kubectl get pods -n kube-system | Select-String "csi-smb"
```

### 6. Troubleshooting Tests

If something fails, run these diagnostic commands:

```powershell
# Get Arc agent logs
kubectl logs -n azure-arc -l app.kubernetes.io/component=connect-agent

# Get Container Apps controller logs
kubectl logs -n logicapps-aca-ns -l app=containerapp-controller

# Get extension installation status
az k8s-extension show `
  --cluster-type connectedClusters `
  --cluster-name <cluster-name> `
  --resource-group <rg-name> `
  --name logicapps-aca-extension `
  --query "installState"

# Check for any failed pods
kubectl get pods --all-namespaces --field-selector=status.phase!=Running

# View recent events
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | Select-Object -Last 20

# Check deployment errors in Azure
az deployment group list --resource-group <rg-name> --query "[?properties.provisioningState=='Failed']"
```

## Test Checklist

### Before Deployment
- [ ] Azure CLI installed (v2.40+)
- [ ] kubectl installed (v1.28+)
- [ ] Helm installed (v3.0+)
- [ ] PowerShell 5.1 or later
- [ ] Azure CLI extensions available
- [ ] Logged into Azure (`az login`)
- [ ] Correct subscription selected (`az account set`)
- [ ] Service principal created with proper permissions
- [ ] Parameters file updated (spnClientId, spnClientSecret, spnTenantId, sqlAdminPassword)
- [ ] ARM templates validated
- [ ] Resource group created

### During Deployment
- [ ] Monitor deployment progress
- [ ] Check for any error messages
- [ ] Verify resource creation in Azure Portal
- [ ] Watch for extension installation completion

### After Deployment
- [ ] AKS cluster created and running
- [ ] Arc connection established
- [ ] Container Apps extension installed
- [ ] Custom location created
- [ ] Connected environment ready
- [ ] SQL Server and database accessible
- [ ] Storage account and file share created
- [ ] SMB CSI driver installed
- [ ] Pods running in logicapps-aca-ns namespace
- [ ] Logic App deployed and accessible
- [ ] Workflow triggers responding

## Expected Deployment Times

| Component | Expected Duration |
|-----------|------------------|
| Resource Provider Registration | 2-3 minutes |
| Log Analytics Workspace | 1-2 minutes |
| AKS Cluster Creation | 10-15 minutes |
| SQL Server & Database | 3-5 minutes |
| Storage Account & File Share | 2-3 minutes |
| SMB CSI Driver Installation | 2-3 minutes |
| Arc Connection | 5-7 minutes |
| Container Apps Extension | 5-10 minutes |
| Custom Location | 1-2 minutes |
| Connected Environment | 2-3 minutes |
| Logic App Deployment | 3-5 minutes |
| **Total** | **30-45 minutes** |

## Common Issues & Solutions

### Issue 1: Azure CLI Extension Not Found
**Solution:**
```powershell
az extension add --name connectedk8s --upgrade --yes
az extension add --name k8s-extension --upgrade --yes
az extension add --name customlocation --upgrade --yes
az extension add --name containerapp --upgrade --yes
```

### Issue 2: kubectl Cannot Connect to Cluster
**Solution:**
```powershell
az aks get-credentials --resource-group <rg-name> --name <aks-cluster-name> --admin --overwrite-existing
kubectl config use-context <aks-cluster-name>-admin
```

### Issue 3: Arc Connection Fails
**Solution:**
```powershell
# Ensure service principal has proper permissions
# Re-run Arc connection
az connectedk8s connect `
  --resource-group <rg-name> `
  --name <cluster-name> `
  --location <location>
```

### Issue 4: Extension Installation Pending
**Solution:**
```powershell
# Wait for extension to complete (can take 5-10 minutes)
# Check status
az k8s-extension show `
  --cluster-type connectedClusters `
  --cluster-name <cluster-name> `
  --resource-group <rg-name> `
  --name logicapps-aca-extension `
  --query "provisioningState"
```

### Issue 5: SQL Connection Fails
**Solution:**
```powershell
# Verify firewall rules
az sql server firewall-rule list --resource-group <rg-name> --server <sql-server-name>

# Add your IP if needed
az sql server firewall-rule create `
  --resource-group <rg-name> `
  --server <sql-server-name> `
  --name AllowMyIP `
  --start-ip-address <your-ip> `
  --end-ip-address <your-ip>
```

## Success Criteria

Your deployment is successful when:

1. ✅ All Azure resources show "Succeeded" provisioning state
2. ✅ AKS cluster nodes are in "Ready" state
3. ✅ Arc connection shows "Connected" status
4. ✅ Container Apps extension shows "Succeeded" install state
5. ✅ Custom location shows "Succeeded" provisioning state
6. ✅ All pods in logicapps-aca-ns namespace are "Running"
7. ✅ SQL Server is accessible (port 1433 open)
8. ✅ Storage account shows "Available" status
9. ✅ Logic App responds to HTTP triggers
10. ✅ Workflows execute successfully

## Next Steps After Testing

If all tests pass:
1. Deploy your actual Logic App workflows
2. Configure API connections
3. Set up monitoring and alerts
4. Implement CI/CD pipelines
5. Configure scaling policies
6. Set up backup and disaster recovery

## Support & Resources

- **Documentation**: [Hybrid Logic Apps Requirements](https://learn.microsoft.com/en-us/azure/logic-apps/set-up-standard-workflows-hybrid-deployment-requirements)
- **Test Script**: `.\TestDeployment.ps1`
- **Deployment Script**: `.\DeployHybridLogicApps.ps1`
- **Issues**: [GitHub Issues](https://github.com/microsoft/azure_arc/issues)

````
