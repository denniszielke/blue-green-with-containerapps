param environmentName string
param location string = resourceGroup().location
param appInsightsInstrumentationKey string
param containerImage string

resource daprexplorer 'Microsoft.App/containerapps@2022-01-01-preview' = {
  name: 'js-explorer'
  kind: 'containerapp'
  location: location
  properties: {
    managedEnvironmentId: resourceId('Microsoft.App/managedEnvironments', environmentName)
    configuration: {
      activeRevisionsMode: 'single'
      ingress: {
        external: true
        targetPort: 3000
        allowInsecure: false    
        transport: 'Auto'
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      dapr: {
        enabled: true
        appId: 'js-explorer'
        appPort: 3000
        appProtocol: 'http'
      }
    }
    template: {
      containers: [
        {
          image: containerImage
          name: 'js-explorer'
          resources: {
            cpu: '0.5'
            memory: '1Gi'
          }
          env:[
            {
              name: 'HTTP_PORT'
              value: '3000'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 4
      }
    }
  }
}
