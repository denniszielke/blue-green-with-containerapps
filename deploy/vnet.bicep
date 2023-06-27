param location string = resourceGroup().location

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
          addressPrefix: '10.0.8.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          delegations: [
            {
              name: 'Microsoft.App.testClients'
              properties: {
                serviceName: 'Microsoft.App/environments'
                actions: [
                  'Microsoft.Network/virtualNetworks/subnets/join/action'
                ]
              }
            }
          ]
          // routeTable: {
          //   id: egressRoutingTable.id
          // }
        }
      }
      {
        name: 'aca-apps'
        properties: {
          addressPrefix: '10.0.16.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          delegations: [
            {
              name: 'Microsoft.App.testClients'
              properties: {
                serviceName: 'Microsoft.App/environments'
                actions: [
                  'Microsoft.Network/virtualNetworks/subnets/join/action'
                ]
              }
            }
          ]
          // routeTable: {
          //   id: egressRoutingTable.id
          // }
        }
      }
    ]
  }
}

resource egressRoutingTable 'Microsoft.Network/routeTables@2020-11-01' = {
  name: 'forceroute'
  location: location
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'egress-fwrn'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: '10.1.3.4'
          hasBgpOverride: false
        }
      }
    ]
  }
}
