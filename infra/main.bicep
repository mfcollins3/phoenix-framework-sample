targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

@description('Name of the Application Insights resource to be created')
param applicationInsightsName string = ''

@description('Name of the Application Insights dashboard to be created')
param applicationInsightsDashboardName string = ''

@description('Name of the Azure Container Apps environment to be created')
param containerAppsEnvironmentName string = ''

@description('Name of the Azure Container Registry to be created')
param containerRegistryName string = ''

@description('Name of the Log Analytics workspace to be created')
param logAnalyticsName string = ''

@description('Name of the resource group to own the Azure resources')
param resourceGroupName string = ''

@description('Name of the web application to be created')
param webAppName string = ''

var abbrs = loadJsonContent('./abbreviations.json')

var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

// Tags that should be applied to all resources.
// 
// Note that 'azd-service-name' tags should be applied separately to service host resources.
// Example usage:
//   tags: union(tags, { 'azd-service-name': <service name in azure.yaml> })
var tags = {
  'azd-env-name': environmentName
}

resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

module monitoring 'br/public:avm/ptn/azd/monitoring:0.1.1' = {
  name: 'monitoring'
  scope: rg
  params: {
    applicationInsightsName: !empty(applicationInsightsName) ? applicationInsightsName : '${abbrs.insightsComponents}${resourceToken}'
    logAnalyticsName: !empty(logAnalyticsName) ? logAnalyticsName : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsDashboardName: !empty(applicationInsightsDashboardName) ? applicationInsightsDashboardName : '${abbrs.portalDashboards}${resourceToken}'
    location: location
    tags: tags
  }
}

module containerApps 'br/public:avm/ptn/azd/container-apps-stack:0.1.1' = {
  name: 'containerApps'
  scope: rg
  params: {
    containerAppsEnvironmentName: !empty(containerAppsEnvironmentName) ? containerAppsEnvironmentName : '${abbrs.appManagedEnvironments}${resourceToken}'
    containerRegistryName: !empty(containerRegistryName) ? containerRegistryName : '${abbrs.containerRegistryRegistries}${resourceToken}'
    logAnalyticsWorkspaceResourceId: monitoring.outputs.logAnalyticsWorkspaceResourceId
    acrAdminUserEnabled: true
    acrSku: 'Basic'
    appInsightsConnectionString: monitoring.outputs.applicationInsightsConnectionString
    daprAIInstrumentationKey: monitoring.outputs.applicationInsightsInstrumentationKey
    enableTelemetry: true
    location: location
    tags: tags
    zoneRedundant: false
  }
}

module webIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  name: 'webIdentity'
  scope: rg
  params: {
    name: '${abbrs.managedIdentityUserAssignedIdentities}web-${resourceToken}'
    location: location
  }
}

module web 'br/public:avm/ptn/azd/container-app-upsert:0.1.2' = {
  name: 'web'
  scope: rg
  params: {
    name: !empty(webAppName) ? webAppName : '${abbrs.appContainerApps}web-${resourceToken}'
    containerAppsEnvironmentName: containerApps.outputs.environmentName
    containerRegistryName: containerApps.outputs.registryName
    containerMaxReplicas: 1
    containerMinReplicas: 1
    env: [
      {
        name: 'SECRET_KEY_BASE'
        value: 'eBLbmGlctHX9gKLVdI+SS165KAKfGIf7wpfFBJU7yrxjWy0xAyvxJDI/DfZ29TSw'
      }
      {
        name: 'PORT'
        value: '80'
      }
    ]
    identityType: 'UserAssigned'
    identityName: webIdentity.name
    userAssignedIdentityResourceId: webIdentity.outputs.resourceId
    identityPrincipalId: webIdentity.outputs.principalId
    location: location
    tags: union(tags, { 'azd-service-name': 'web' })
  }
}

output APPLICATIONINSIGHTS_CONNECTION_STRING string = monitoring.outputs.applicationInsightsConnectionString
output APPLICATIONINSIGHTS_NAME string = monitoring.outputs.applicationInsightsName
output AZURE_CONTAINER_ENVIRONMENT_NAME string = containerApps.outputs.environmentName
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerApps.outputs.registryLoginServer
output AZURE_CONTAINER_REGISTRY_NAME string = containerApps.outputs.registryName
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output WEB_APP_URL string = web.outputs.uri
