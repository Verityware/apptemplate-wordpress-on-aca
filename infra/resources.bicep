targetScope = 'resourceGroup'

@description('A descriptive name for the resources to be created in Azure')
param applicationName string
@description('This is the fqdn exposed by this wordpress instance. Note this must much the certificate')
param wordpressFqdn string
@description('Naming principles implementation')
param naming object
param tags object = {}
@description('The location where resources will be deployed')
param location string
param mariaDBAdmin string = 'db_admin'
@secure()
param mariaDBPassword string
@description('The principal ID of the service principal that will be deploying the resources. If not specified, the current user will be used.')
param principalId string = ''
@description('The redis cache deployment option. Valid values are: managed, container, local.')
param redisDeploymentOption string = 'container'
@description('The wordpress container image to use.')
param wordpressImage string = 'kpantos/wordpress-alpine-php:latest'

var resourceNames = {
  storageAccount: naming.storageAccount.nameUnique
  keyVault: naming.keyVault.name
  redis: naming.redisCache.name
  mariadb: naming.mariadbDatabase.name
  containerAppName: 'wordpress'
  applicationGateway: naming.applicationGateway.name
}
var secretNames = {
  connectionString: 'storageConnectionString'
  storageKey: 'storageKey'
  certificateKeyName: 'certificateName'
  redisConnectionString: 'redisConnectionString'
  mariaDBPassword: 'mariaDBPassword'
  redisPrimaryKeyKeyName: 'redisPrimaryKey'
  redisPasswordName: 'redisPassword'
}

//Log Analytics - App insights
module logAnalytics 'modules/appInsights.module.bicep' = {
  name: 'loganalytics-deployment'
  params: {
    location: location
    tags: tags
    name: applicationName
  }
}

//2. Storage
module storage 'modules/storage.module.bicep' = {
  name: 'storage-deployment'
  dependsOn:[keyVault]
  params: {
    location: location
    kind: 'StorageV2'
    skuName: 'Standard_LRS'
    name: resourceNames.storageAccount
    secretNames: secretNames
    keyVaultName: resourceNames.keyVault
    tags: tags
  }
}

//4. Keyvault
module keyVault 'modules/keyvault.module.bicep' ={
  name: 'keyVault-deployment'
  params: {
    name: resourceNames.keyVault
    location: location
    skuName: 'premium'
    tags: tags
    secrets: [
      {
        name: secretNames.mariaDBPassword
        value: mariaDBPassword
      }
    ]
    accessPolicies: (!empty(principalId))? [
      {
        objectId: principalId
        tenantId: subscription().tenantId
        permissions: {
          secrets: [
            'get'
          ]
        }
      }
    ] : []
  }  
}

//5. Container Apps
//Get a reference to key vault
resource vault 'Microsoft.KeyVault/vaults@2019-09-01' existing = {
  name: resourceNames.keyVault
}
module wordpressapp 'containerapp.bicep' = {
  name: 'wordpressapp-deployment'
  dependsOn:[
    keyVault
    storage
    logAnalytics
  ]
  params: {
    tags: tags
    location: location    
    containerAppName: resourceNames.containerAppName
    wordpressFqdn: wordpressFqdn
    infraSnetId: 'network.outputs.infraSnetId'
    logAnalytics: logAnalytics.outputs.logAnalytics
    storageAccountName: resourceNames.storageAccount
    storageAccountKey: vault.getSecret(secretNames.storageKey)
    storageShareName: storage.outputs.fileshareName
    dbHost: 'mariaDB.outputs.hostname'
    dbUser: mariaDBAdmin
    dbPassword: vault.getSecret(secretNames.mariaDBPassword)
    redisDeploymentOption: redisDeploymentOption
    redisManagedFqdn: (!empty(redisDeploymentOption) && redisDeploymentOption == 'managed')? 'redis.outputs.redisHost' : ''
    redisManagedPassword: (!empty(redisDeploymentOption) && redisDeploymentOption == 'managed')? vault.getSecret(secretNames.redisPasswordName) : ''
    wordpressImage: wordpressImage
  }
}
