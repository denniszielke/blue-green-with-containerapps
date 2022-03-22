param location string = 'eastus'// resourceGroup().location
param storageAccountName string

resource appstorage 'Microsoft.Storage/storageAccounts@2021-02-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
    tier: 'Standard'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
  }
}

resource files 'Microsoft.Storage/storageAccounts/fileServices@2021-08-01' = {
  name: 'default'
  parent: appstorage
  properties: {
  }
}

resource share 'Microsoft.Storage/storageAccounts/fileServices/shares@2021-08-01' = {
  name: 'files'
  parent: files
  properties: {
  }
}

output filesEndpoint string = appstorage.name
output filesAccessKey string = '${listKeys(appstorage.id, appstorage.apiVersion).keys[0].value}'
