param location string = resourceGroup().location
param environmentName string = 'env-${resourceGroup().name}'
param explorerImageTag string 
param calculatorImageTag string
param containerRegistryOwner string

module redis 'redis.bicep' = {
  name: 'container-app-redis'
  params: {
    redisName: 'rds-${environmentName}'
  }
}

module logging 'logging.bicep' = {
  name: 'container-app-logging'
  params: {
    logAnalyticsWorkspaceName: 'logs-${environmentName}'
    appInsightsName: 'appins-${environmentName}'
  }
}

module daprexplorer 'app-dapr-explorer.bicep' = {
  name: 'container-app-dapr-explorer'
  params: {
    containerImage: 'ghcr.io/${containerRegistryOwner}/container-apps/js-dapr-explorer:${explorerImageTag}'
    environmentName: environmentName
    appInsightsInstrumentationKey: logging.outputs.appInsightsInstrumentationKey
  }
}

module jscalcbackend 'app-js-calc-backend.bicep' = {
  name: 'container-app-js-calc-backend'
  params: {
    containerImage: 'ghcr.io/${containerRegistryOwner}/container-apps/js-calc-backend:${calculatorImageTag}'
    environmentName: environmentName
    appInsightsInstrumentationKey: logging.outputs.appInsightsInstrumentationKey
  }
}

module jscalcfrontend 'app-js-calc-frontend.bicep' = {
  name: 'container-app-js-calc-frontend'
  params: {
    containerImage: 'ghcr.io/${containerRegistryOwner}/container-apps/js-calc-frontend:${calculatorImageTag}'
    environmentName: environmentName
    appInsightsInstrumentationKey: logging.outputs.appInsightsInstrumentationKey
    redisHost: redis.outputs.redisHost
    redisPassword: redis.outputs.redisPassword
  }
}
