@description('The location in which all resources should be deployed.')
param location string = resourceGroup().location

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string = 'Prodution'

@description('Domain name to use for App Gateway')
param customDomainName string = 'contoso.com'

@description('The certificate data for app gateway TLS termination. The value is base64 encoded')
@secure()
param appGatewayListenerCertificate string

@description('Optional. When true will deploy a cost-optimised environment for development purposes. Note that when this param is true, the deployment is not suitable or recommended for Production environments. Default = false.')
param developmentEnvironment bool = false

// open AI resources
param openAiServiceName string = '' // Set in main.parameters.json
@description('Location for the OpenAI resource group')
@allowed(['canadaeast', 'eastus', 'eastus2', 'francecentral', 'switzerlandnorth', 'uksouth', 'japaneast', 'northcentralus', 'australiaeast', 'swedencentral'])
@metadata({
  azd: {
    type: 'location'
  }
})
param openAiResourceGroupLocation string = location
param openAiSkuName string = 'S0'

param chatGptDeploymentName string = '' // Set in main.parameters.json
param chatGptDeploymentCapacity int = 20
param chatGptModelName string = '' // Set in main.parameters.json
param chatGptModelVersion string = '1106-preview'
param embeddingDeploymentName string = '' // Set in main.parameters.json
param embeddingDeploymentCapacity int = 30
param embeddingModelName string = '' // Set in main.parameters.json

@description('Use Application Insights for monitoring and performance tracing')
param useApplicationInsights bool = true

param logAnalyticsName string = ''
param applicationInsightsDashboardName string = ''
param applicationInsightsName string = ''

@description('SSH Key or password for the Virtual Machine. SSH key is recommended.')
@secure()
param adminPasswordOrKey string

var abbrs = loadJsonContent('abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, resourceGroup().name, location))
// ---- Availability Zones ----
var availabilityZones = [ '1', '2', '3' ]
var tags = { 'azd-env-name': environmentName }

// Deploy vnet with subnets and NSGs
module networkModule 'modules/network.bicep' = {
  name: 'networkDeploy'
  params: {
    location: location
    baseName: resourceToken
    developmentEnvironment: developmentEnvironment
  }
}

// Deploy storage account with private endpoint and private DNS zone
// module storageModule 'modules/storage.bicep' = {
//   name: 'storageDeploy'
//   params: {
//     location: location
//     baseName: resourceToken
//     vnetName: networkModule.outputs.vnetNName
//     privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
//   }
// }

// ---- Log Analytics workspace ----
module logWorkspace './modules/monitor/monitoring.bicep' = if (useApplicationInsights) {
  name: 'monitoring'  
  params: {
    location: location
    tags: tags
    logAnalyticsName: !empty(logAnalyticsName) ? logAnalyticsName : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: !empty(applicationInsightsName) ? applicationInsightsName : '${abbrs.insightsComponents}${resourceToken}'
    applicationInsightsDashboardName: !empty(applicationInsightsDashboardName) ? applicationInsightsDashboardName : '${abbrs.portalDashboards}${resourceToken}'
  }
}

// Deploy a Key Vault with a private endpoint and DNS zone
module secretsModule 'modules/secrets.bicep' = {
  name: 'secretsDeploy'
  params: {
    location: location
    baseName: resourceToken
    vnetName: networkModule.outputs.vnetNName
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    appGatewayListenerCertificate: appGatewayListenerCertificate  
  }
}

module cosmosDBModule 'modules/cosmosdb.bicep' = {
  name: 'cosmosDBDeploy'
  params: {
    location: location
    vnetName: networkModule.outputs.vnetNName
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
  }
}

module openAiModule 'modules/ai/cognitiveservices.bicep' = {
  name: 'openaiDeploy'
  params: {
    name: !empty(openAiServiceName) ? openAiServiceName : 'openai-${resourceToken}'
    location: openAiResourceGroupLocation
    tags: tags
    sku: {
      name: openAiSkuName
    }
    deployments: [
      {
        name: chatGptDeploymentName
        model: {
          format: 'OpenAI'
          name: chatGptModelName
          version: chatGptModelVersion
        }
        sku: {
          name: 'Standard'
          capacity: chatGptDeploymentCapacity
        }
      }
      {
        name: 'ftb-dtt-chatgnb-turbo-prd2'
        model: {
          format: 'OpenAI'
          name: chatGptModelName
          version: chatGptModelVersion
        }
        sku: {
          name: 'Standard'
          capacity: chatGptDeploymentCapacity
        }
      }  
    ]
  }
}

// Deploy a web app
module webappModule 'modules/webapp.bicep' = {
  name: 'webappDeploy'
  params: {
    location: location
    baseName: resourceToken
    developmentEnvironment: developmentEnvironment   
    keyVaultName: secretsModule.outputs.keyVaultName    
    vnetName: networkModule.outputs.vnetNName
    appServicesSubnetName: networkModule.outputs.appServicesSubnetName
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    logWorkspaceName: logWorkspace.outputs.logAnalyticsWorkspaceName
   }
}

//Deploy an Azure Application Gateway with WAF v2 and a custom domain name.
module gatewayModule 'modules/gateway.bicep' = {
  name: 'gatewayDeploy'
  params: {
    location: location
    baseName: resourceToken
    developmentEnvironment: developmentEnvironment
    availabilityZones: availabilityZones
    customDomainName: customDomainName
    appName: webappModule.outputs.appName
    vnetName: networkModule.outputs.vnetNName
    appGatewaySubnetName: networkModule.outputs.appGatewaySubnetName
    keyVaultName: secretsModule.outputs.keyVaultName
    gatewayCertSecretUri: secretsModule.outputs.gatewayCertSecretUri
    logWorkspaceName: logWorkspace.name
   }
   dependsOn: [
    webappModule 
  ]
}

// deploy GitLab runner on Azure virtual machine
module gitlabRunner 'modules/pipelines/gitlab-runner.bicep' = {
  name: 'gitlab-runner'
  params: {
    adminUsername: 'glrunner'
    authenticationType: 'sshPublicKey'    
    location: location
    adminPasswordOrKey:adminPasswordOrKey
    vnetName: networkModule.outputs.vnetNName
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
  }
}

// Add Role Assignements for Managed Identity
module openAiRoleUser 'modules/security/role.bicep' = {
  name: 'openai-role-user'
  params: {
    principalId: webappModule.outputs.identityPrincipalId
    roleDefinitionId: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    webappModule 
  ]
}
