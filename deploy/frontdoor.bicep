param location string = resourceGroup().location
param frontdoorName string 
param privateLinkServiceId string
param appHostName string

var frontDoorProfileName = '${frontdoorName}-fd'
var frontDoorEndpointName = '${frontdoorName}-fd-endpoint'
var frontDoorOriginGroupName = '${frontdoorName}-fd-og'
var frontDoorOriginRouteName = '${frontdoorName}-fd-route'
var frontDoorOriginName = '${frontdoorName}-fd-origin'

resource privateLinkService 'Microsoft.Network/privateLinkServices@2022-01-01' existing = {
  name: frontdoorName
}

var privateLinkEndpointConnectionId = length(privateLinkService.properties.privateEndpointConnections) > 0 ? filter(privateLinkService.properties.privateEndpointConnections, (connection) => connection.properties.privateLinkServiceConnectionState.description == 'frontdoor')[0].id : ''
output privateLinkEndpointConnectionId string = privateLinkEndpointConnectionId

resource frontdoorProfile 'Microsoft.Cdn/profiles@2022-05-01-preview' = {
  name: frontDoorProfileName
  location: 'Global'
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    originResponseTimeoutSeconds: 120
    extendedProperties: {}
  }
}

resource frontDoorEndpoint 'Microsoft.Cdn/profiles/afdendpoints@2022-05-01-preview' = {
  parent: frontdoorProfile
  name: frontDoorEndpointName
  location: 'Global'
  properties: {
    enabledState: 'Enabled'
  }
}

resource frontDoorOriginGroup 'Microsoft.Cdn/profiles/origingroups@2022-05-01-preview' = {
  parent: frontdoorProfile
  name: frontDoorOriginGroupName
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/health'
      probeRequestType: 'HEAD'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 100
    }
    sessionAffinityState: 'Disabled'
  }
}

resource frontDoorOrigin 'Microsoft.Cdn/profiles/origingroups/origins@2022-05-01-preview' = {
  parent: frontDoorOriginGroup
  name: frontDoorOriginName
  properties: {
    hostName: appHostName
    httpPort: 80
    httpsPort: 443
    originHostHeader: appHostName
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    sharedPrivateLinkResource: {
      privateLink: {
        id: privateLinkServiceId
      }
      privateLinkLocation: location
      requestMessage: 'frontdoor'
    }
    enforceCertificateNameCheck: true
  }
}

resource frontDoorOriginRoute 'Microsoft.Cdn/profiles/afdendpoints/routes@2022-05-01-preview' = {
  parent: frontDoorEndpoint
  name: frontDoorOriginRouteName
  properties: {
    originGroup: {
      id: frontDoorOriginGroup.id
    }
    originPath: '/'
    ruleSets: []
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    enabledState: 'Enabled'
  }

  dependsOn: [
    frontDoorOrigin
  ]
}

output fqdn string = frontDoorEndpoint.properties.hostName
