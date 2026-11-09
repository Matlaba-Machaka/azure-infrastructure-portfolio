@description('Azure region for deployment')
param location string = 'southafricanorth'

var suffix = uniqueString(resourceGroup().id)
var acrName = 'acrportfolio${suffix}'
var logAnalyticsName = 'law-containers-${suffix}'
var acaEnvName = 'cae-prod-env'

// 1. Private Azure Container Registry (Admin Disabled for Zero-Trust)
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    adminUserEnabled: false
  }
}

// 2. Log Analytics Workspace for Container Apps
resource law 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// 3. Azure Container Apps Environment
resource acaEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: acaEnvName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: law.properties.customerId
        sharedKey: law.listKeys().primarySharedKey
      }
    }
  }
}

output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
output acaEnvId string = acaEnv.id
