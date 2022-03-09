param environmentName string
param location string = resourceGroup().location
param appInsightsInstrumentationKey string
param redisHost string
param redisPassword string
param containerImage string

resource jscalcfrontendrediscomponent 'Microsoft.App/managedEnvironments/daprComponents@2022-01-01-preview' = {
  name: '${environmentName}/redis'
  kind: 'daprComponents'
  location: location
  properties: {
    componentType : 'state.redis'
    version: 'v1'
    ignoreErrors: false
    initTimeout: '60s'
    secrets: [
      {
        name: 'redis-key'
        value: redisPassword
      }
    ]
    metadata : [
      {
        name: 'redisHost'
        value: '${redisHost}:6379'
      }
      {
        name: 'redisPassword'
        secretRef: 'redis-key'
      }
    ]
    scopes: [
      'js-calc-frontend'
    ]
  }
}

resource jscalcfrontend 'Microsoft.App/containerapps@2022-01-01-preview' = {
  name: 'js-calc-frontend'
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
      secrets: [
      {
        name: 'redis-key'
        value: redisPassword
      }
      ]
      dapr: {
        enabled: true
        appId: 'js-calc-frontend'
        appPort: 8080
        appProtocol: 'http'
      }
    }
    template: {
      containers: [
        {
          image: containerImage
          name: 'js-calc-frontend'
          resources: {
            cpu: '1'
            memory: '2Gi'
          }
          probes: {
            livenessProbe: {
              httpGet: {
                path: '/ping'
                port: 8080
              }
              initialDelaySeconds: 5
              periodSeconds: 5
            }
            readinessProbe: {
              httpGet: {
                path: '/ping'
                port: 8080
              }
              initialDelaySeconds: 5
            }
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
              name: 'ENDPOINT'
              value: 'http://localhost:3500/v1.0/invoke/js-calc-backend/method'
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
    }
  }
}
