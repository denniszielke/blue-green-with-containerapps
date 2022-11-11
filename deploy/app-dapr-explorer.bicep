param environmentName string
param location string = resourceGroup().location
param containerImage string
param appInsightsConnectionString string

resource daprexplorer 'Microsoft.App/containerapps@2022-03-01' = {
  name: 'js-explorer'
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
            cpu: json('0.5')
            memory: '1Gi'
          }
          env:[
            {
              name: 'HTTP_PORT'
              value: '3000'
            }
            {
              name: 'AIC_STRING'
              value: appInsightsConnectionString
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
