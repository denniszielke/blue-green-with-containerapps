param location string = resourceGroup().location
param environmentName string = 'env-${resourceGroup().name}'
param internalOnly bool = false

module redis 'redis.bicep' = {
  name: 'container-app-redis'
  params: {
    redisName: 'rds-${environmentName}'
  }
}

module logging 'logging.bicep' = {
  name: 'container-app-logging'
  params: {
    location: 'eastus'
    logAnalyticsWorkspaceName: 'logs-${environmentName}'
    appInsightsName: 'appins-${environmentName}'
  }
}

// // container app environment
module environment 'environment.bicep' = {
  name: 'container-app-environment'
  params: {
    environmentName: environmentName
    internalOnly: internalOnly
    logAnalyticsCustomerId: logging.outputs.logAnalyticsCustomerId
    logAnalyticsSharedKey: logging.outputs.logAnalyticsSharedKey
    appInsightsInstrumentationKey: logging.outputs.appInsightsInstrumentationKey
    appInsightsConnectionString: logging.outputs.appInsightsConnectionString
  }
}

// module frontdoor 'frontdoor.bicep' = {
//   name: 'frontdoor'
//   params: {
//     frontdoorName: 'appfront'
//     privateLinkServiceId:
//   }
// }
