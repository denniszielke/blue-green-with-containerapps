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
      dapr: {
        enabled: true
        appId: 'js-calc-backend'
        appPort: 8080
        appProtocol: 'http'
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
          probes: [
            {
              type: 'liveness'
              httpGet: {
                path: '/ping'
                port: 8080
                httpHeaders: [
                  {
                    name: 'my-header'
                    value: 'ping'
                  }
                ]
              }
              initialDelaySeconds: 5
              periodSeconds: 3
            }
            {
              type: 'readiness'
              httpGet: {
                path: '/ping'
                port: 8080
                httpHeaders: [
                  {
                    name: 'my-header'
                    value: 'ping'
                  }
                ]
              }
              initialDelaySeconds: 5
              periodSeconds: 3
            }
          ]
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
        minReplicas: 0
        maxReplicas: 4
        rules: [
          {
            name: 'backendrule'
            custom: {
              type: 'http'
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }
  }
}
