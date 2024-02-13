@description('Optional. Cosmos DB account name, max length 44 characters, lowercase')
param cosmosDBAccountName string = 'cosmosdb-account-${uniqueString(resourceGroup().id)}'

@description('Optional. The name for the CosmosDB database')
param cosmosDBDatabaseName string = 'cosmosdb-db-${uniqueString(resourceGroup().id)}'

@description('Optional. The name for the CosmosDB database container')
param cosmosDBContainerName string = 'cosmosdb-container-${uniqueString(resourceGroup().id)}'

param location string = resourceGroup().location

// existing resource name params 
param vnetName string
param privateEndpointsSubnetName string

var cosmosPrivateEndpointName = 'pep-${cosmosDBAccountName}'
var cosmosDnsGroupName = '${cosmosPrivateEndpointName}/default'
var cosmosDnsZoneName = 'privatelink.documents.azure.com'

// ---- Existing resources ----
resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' existing = {
  name: vnetName

  resource privateEndpointsSubnet 'subnets' existing = {
    name: privateEndpointsSubnetName
  }
}

var cosmosDbPrivateEndpointName = 'pep-${cosmosDBAccountName}'

resource cosmosDBAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' = {
  name: cosmosDBAccountName
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    locations: [
      {
        locationName: location
      }
    ]
    enableFreeTier: false
    isVirtualNetworkFilterEnabled: false
    publicNetworkAccess: 'Disabled'
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
  }
}

resource cosmosDBDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-04-15' = {
  parent: cosmosDBAccount
  name: cosmosDBDatabaseName
  location: location
  properties: {
    resource: {
      id: cosmosDBDatabaseName
    }
  }
}

resource cosmosDBContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: cosmosDBDatabase
  name: cosmosDBContainerName
  location: location
  properties: {
    resource: {
      id: cosmosDBContainerName
      partitionKey: {
        paths: [
          '/user_id'
        ]
        kind: 'Hash'
        version: 2
      }
      defaultTtl: 1000
    }
  }
}

// create cosmosdb privare endpoint
resource cosmosprivateEndpoint 'Microsoft.Network/privateEndpoints@2022-11-01' = {
  name: cosmosDbPrivateEndpointName
  location: location
  properties: {
    subnet: {
      id: vnet::privateEndpointsSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: cosmosDbPrivateEndpointName
        properties: {
          privateLinkServiceId: cosmosDBAccount.id
          groupIds: [
            'Sql'
          ]
          requestMessage: ''
        }
      }
    ]
  }
}

resource cosmosDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: cosmosDnsZoneName
  location: 'global'
  properties: {}
}

// create cosmosdb private dns zone
resource cosmosDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: cosmosDnsZone
  name: '${cosmosDnsZoneName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource cosmosDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-11-01' = {
  name: cosmosDnsGroupName
  properties: {
    privateDnsZoneConfigs: [
      {
        name: cosmosDnsZoneName
        properties: {
          privateDnsZoneId: cosmosDnsZone.id
        }
      }
    ]
  }
  dependsOn: [
    cosmosprivateEndpoint
  ]
}

output privateEndpointNetworkInterface string = cosmosprivateEndpoint.properties.networkInterfaces[0].id
