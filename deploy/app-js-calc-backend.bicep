param environmentName string
param location string = resourceGroup().location
param appInsightsConnectionString string
param containerImage string

resource jscalcbackend 'Microsoft.App/containerapps@2022-03-01' = {
  name: 'js-calc-backend'
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
            cpu: 1
            memory: '2Gi'
          } 
          probes: [
            {
              type: 'liveness'
              httpGet: {
                path: '/healthz'
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
                path: '/healthz'
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
              name: 'AIC_STRING'
              value: appInsightsConnectionString
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
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
