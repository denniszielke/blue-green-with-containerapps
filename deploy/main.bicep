param location string = resourceGroup().location
param environmentName string = 'env-${resourceGroup().name}'
param minReplicas int = 0

// // container app environment
module environment 'environment.bicep' = {
  name: 'container-app-environment'
  params: {
    environmentName: environmentName
  }
}
