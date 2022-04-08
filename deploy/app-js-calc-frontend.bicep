param environmentName string
param location string = resourceGroup().location
param appInsightsInstrumentationKey string
param redisHost string
param redisPassword string
param containerImage string
param filesAccountName string
param filesAccountKey  string

resource jscalcfrontendrediscomponent 'Microsoft.App/managedEnvironments/daprComponents@2022-01-01-preview' = {
  name: '${environmentName}/redis'
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

// resource jscalcmount 'Microsoft.App/managedEnvironments/storages@2022-01-01-preview' = {
//   name: '${environmentName}/files'
//   properties: {
//     azureFile: {
//       accountName: filesAccountName
//       accountKey: filesAccountKey
//       shareName: 'files'
//       accessMode: 'ReadWrite'
//     }
//   }
// }

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
          // volumeMounts: [
          //   {
          //     mountPath: '/mnt/files'
          //     volumeName: 'files'
          //   }
          // ]
          env:[
            {
              name: 'PORT'
              value: '8080'
            }
            {
              name: 'WRITEPATH'
              value: '/mnt/files/'
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
            {
              name: 'CACHEENDPOINT'
              value: 'http://localhost:3500/v1.0/state/redis'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 4
        rules: [
          {
            name: 'frontendrule'
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
