param redisName string
param location string = resourceGroup().location

resource redisCache 'Microsoft.Cache/Redis@2019-07-01' = {
  name: redisName
  location: resourceGroup().location
  properties: {
    enableNonSslPort: true
    sku: {
      name: 'Basic'
      family: 'C'
      capacity: 0
    }
  }
}

output redisHost string = redisCache.properties.hostName
output redisPassword string = redisCache.listKeys().primaryKey
