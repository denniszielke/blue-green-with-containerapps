param environmentName string
param redisName string = 'rds-${environmentName}'
param location string = resourceGroup().location
param logAnalyticsCustomerId string
param logAnalyticsSharedKey string
param appInsightsInstrumentationKey string
param appInsightsConnectionString string
param internalOnly bool

resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' existing = {
  name: 'vnet-${resourceGroup().name}'
}

resource redisCache 'Microsoft.Cache/Redis@2019-07-01' = {
  name: redisName
  location: resourceGroup().location
  properties: {
    enableNonSslPort: true
    sku: {
      name: 'Basic'
      family: 'C'
      capacity: 0
    }
  }
}

resource environment 'Microsoft.App/managedEnvironments@2023-05-02-preview' = {
  name: environmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsCustomerId
        sharedKey: logAnalyticsSharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'consumption'
        workloadProfileType: 'Consumption'
      }
      {
        name: 'd4-compute'
        workloadProfileType: 'D4'
        minimumCount: 1
        maximumCount: 3
      }
    ]
    daprAIConnectionString: appInsightsConnectionString
    daprAIInstrumentationKey: appInsightsInstrumentationKey
    vnetConfiguration: {
      infrastructureSubnetId: '${vnet.id}/subnets/aca-apps'
      internal: false
    }
    peerAuthentication: {
      mtls: {
          enabled: true
      }
  }
    zoneRedundant: false
  }
}

output location string = location
output environmentId string = environment.id
output environmentStaticIp string = environment.properties.staticIp
output environmentDefaultDomain string = environment.properties.defaultDomain
