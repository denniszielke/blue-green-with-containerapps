param environmentName string
param location string = resourceGroup().location
param appInsightsInstrumentationKey string
param containerImage string

resource jscalcbackend 'Microsoft.App/containerapps@2022-01-01-preview' = {
  name: 'js-calc-backend'
  kind: 'containerapp'
  location: location
  properties: {
    managedEnvironmentId: resourceId('Microsoft.App/managedEnvironments', environmentName)
    configuration: {
      activeRevisionsMode: 'single'
      ingress: {
        external: true
        targetPort: 8080
        allowInsecure: false    
        transport: 'Auto'
      }
    }
    template: {
      containers: [
        {
          image: containerImage
          name: 'js-calc-backend'
          resources: {
            cpu: '1'
            memory: '2Gi'
          }
          env:[
            {
              name: 'PORT'
              value: '8080'
            }
            {
              name: 'VERSION'
              value: 'frontend - blue'
            }
            {
              name: 'INSTRUMENTATIONKEY'
              value: appInsightsInstrumentationKey
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 4
        rules: [
          {
            name: 'httprule'
            custom: {
              type: 'http'
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
      dapr: {
        enabled: true
        appPort: 8080
        appId: 'js-calc-backend'
      }
    }
  }
}
