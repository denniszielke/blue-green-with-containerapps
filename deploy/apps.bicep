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


module storage 'storage.bicep' = {
  name: 'container-app-storage'
  params: {
    storageAccountName: 'strg${resourceGroup().name}'
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
    appInsightsConnectionString: logging.outputs.appInsightsConnectionString
  }
}

module jscalcbackend 'app-js-calc-backend.bicep' = {
  name: 'container-app-js-calc-backend'
  params: {
    containerImage: 'ghcr.io/${containerRegistryOwner}/container-apps/js-calc-backend:${calculatorImageTag}'
    environmentName: environmentName
    appInsightsConnectionString: logging.outputs.appInsightsConnectionString
  }
}

module jscalcfrontend 'app-js-calc-frontend.bicep' = {
  name: 'container-app-js-calc-frontend'
  params: {
    containerImage: 'ghcr.io/${containerRegistryOwner}/container-apps/js-calc-frontend:${calculatorImageTag}'
    environmentName: environmentName
    appInsightsConnectionString: logging.outputs.appInsightsConnectionString
    redisHost: redis.outputs.redisHost
    redisPassword: redis.outputs.redisPassword
    filesAccountName: storage.outputs.filesEndpoint
    filesAccountKey: storage.outputs.filesAccessKey
  }
}

// az deployment group create -g dzca15cgithub -f ./deploy/apps.bicep -p explorerImageTag=latest -p calculatorImageTag=latest  -p containerRegistryOwner=denniszielke
