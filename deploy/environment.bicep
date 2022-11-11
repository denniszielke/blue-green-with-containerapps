param environmentName string
param redisName string = 'rds-${environmentName}'
param location string = resourceGroup().location
param logAnalyticsCustomerId string
param logAnalyticsSharedKey string
param appInsightsInstrumentationKey string
param appInsightsConnectionString string
param internalOnly bool

resource subnetNSG 'Microsoft.Network/networkSecurityGroups@2022-01-01' = {
  name: 'nsg-${resourceGroup().name}'
  location: location
  properties: {
    securityRules: [
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: 'vnet-${resourceGroup().name}'
  location: resourceGroup().location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/19'
      ]
    }
    subnets: [
      {
        name: 'gateway'
        properties: {
          addressPrefix: '10.0.0.0/24'
          networkSecurityGroup: {
            id: subnetNSG.id
          }
        }
      }
      {
        name: 'jumpbox'
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: subnetNSG.id
          }
        }
      }
      {
        name: 'apim'
        properties: {
          addressPrefix: '10.0.2.0/24'
        }
      }
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: '10.0.3.0/24'
        }
      }
      {
        name: 'aca-control'
        properties: {
          addressPrefix: '10.0.8.0/23'
          networkSecurityGroup: {
            id: subnetNSG.id
          }
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'aca-apps'
        properties: {
          addressPrefix: '10.0.16.0/23'
          networkSecurityGroup: {
            id: subnetNSG.id
          }
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
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


resource environment 'Microsoft.App/managedEnvironments@2022-06-01-preview' = {
  name: environmentName
  location: location
  sku: {
    name: 'Consumption'
  }
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsCustomerId
        sharedKey: logAnalyticsSharedKey
      }
    }
    daprAIConnectionString: appInsightsConnectionString
    daprAIInstrumentationKey: appInsightsInstrumentationKey
    vnetConfiguration: {
      dockerBridgeCidr: '172.17.0.1/16'
      infrastructureSubnetId: '${vnet.id}/subnets/aca-control'
      internal: internalOnly
      platformReservedCidr: '10.2.0.0/24'
      platformReservedDnsIP: '10.2.0.10'
      runtimeSubnetId: '${vnet.id}/subnets/aca-apps'
      outboundSettings : {
        outBoundType: 'LoadBalancer'
      } 
    }
    zoneRedundant: false
  }
}

output location string = location
output environmentId string = environment.id
output environmentStaticIp string = environment.properties.staticIp
output environmentDefaultDomain string = environment.properties.defaultDomain
