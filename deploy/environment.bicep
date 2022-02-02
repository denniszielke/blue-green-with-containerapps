param environmentName string
param logAnalyticsWorkspaceName string = 'logs-${environmentName}'
param appInsightsName string = 'appins-${environmentName}'
param redisName string = 'rds-${environmentName}'
param location string = resourceGroup().location

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2020-08-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: any({
    retentionInDays: 30
    features: {
      searchVersion: 1
      legacy: 0
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    sku: {
      name: 'PerGB2018'
    }
  })
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
        }
      }
      {
        name: 'jumpbox'
        properties: {
          addressPrefix: '10.0.1.0/24'
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
          addressPrefix: '10.0.8.0/21'
        }
      }
      {
        name: 'aca-apps'
        properties: {
          addressPrefix: '10.0.16.0/21'
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

resource appInsights 'Microsoft.Insights/components@2020-02-02-preview' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: { 
    ApplicationId: appInsightsName
    Application_Type: 'web'
    Flow_Type: 'Redfield'
    Request_Source: 'CustomDeployment'
  }
}

resource environment 'Microsoft.Web/kubeEnvironments@2021-03-01' = {
  name: environmentName
  location: location
  properties: {
    type: 'managed'
    internalLoadBalancerEnabled: false
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    containerAppsConfiguration: {
      daprAIInstrumentationKey: appInsights.properties.InstrumentationKey
      controlPlaneSubnetResourceId : '${vnet.id}/subnets/aca-control'
      appSubnetResourceId: '${vnet.id}/subnets/aca-apps'
      internalOnly: false
    }
  }
}

output location string = location
output environmentId string = environment.id
