@description('Azure region for deployment')
param location string = 'southafricanorth'

@description('Existing ACR Name from foundation deployment')
param acrName string

var suffix = uniqueString(resourceGroup().id)
var acaEnvId = resourceId('Microsoft.App/managedEnvironments', 'cae-prod-env')
var planName = 'asp-bluegreen-prod'
var webAppName = 'webapp-bluegreen-${suffix}'

// Built-in Role ID: AcrPull
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

var imageUri = '${acr.properties.loginServer}/custom-php-web:v1'

// 1. User-Assigned Managed Identity for Container App (Breaks circular RBAC dependency)
resource acaIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-aca-acrpull'
  location: location
}

resource acaAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, acaIdentity.id, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: acaIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// 2. Serverless Azure Container App
resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'ca-php-frontend'
  location: location
  dependsOn: [acaAcrPull]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${acaIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: acaEnvId
    configuration: {
      ingress: {
        external: true
        targetPort: 80
      }
      registries: [
        {
          server: acr.properties.loginServer
          identity: acaIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'php-frontend'
          image: imageUri
          env: [
            {
              name: 'APP_VERSION'
              value: 'v1.0-CONTAINER-APPS'
            }
          ]
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
    }
  }
}

// 3. Standard S1 App Service Plan (Required for Blue/Green Deployment Slots)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: planName
  location: location
  sku: {
    name: 'S1'
    tier: 'Standard'
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

// 4. Production Web App (Blue v1.0)
resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: webAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOCKER|${imageUri}'
      acrUseManagedIdentityCreds: true
      appSettings: [
        {
          name: 'APP_VERSION'
          value: 'v1.0-BLUE (Production)'
        }
        {
          name: 'WEBSITES_PORT'
          value: '80'
        }
      ]
    }
  }
}

// Grant Production Slot AcrPull
resource prodAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, webApp.id, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: webApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// 5. Staging Deployment Slot (Green v2.0)
resource stagingSlot 'Microsoft.Web/sites/slots@2023-01-01' = {
  parent: webApp
  name: 'staging'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOCKER|${imageUri}'
      acrUseManagedIdentityCreds: true
      appSettings: [
        {
          name: 'APP_VERSION'
          value: 'v2.0-GREEN (Staging)'
        }
        {
          name: 'WEBSITES_PORT'
          value: '80'
        }
      ]
    }
  }
}

// Grant Staging Slot AcrPull
resource stagingAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, stagingSlot.id, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: stagingSlot.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output webAppName string = webApp.name
output productionUrl string = 'https://${webApp.properties.defaultHostName}'
output stagingUrl string = 'https://${stagingSlot.properties.defaultHostName}'
