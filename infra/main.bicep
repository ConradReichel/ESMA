param location string = resourceGroup().location
param appName string = 'esma-${uniqueString(resourceGroup().id)}'
param databaseName string = 'esma${uniqueString(resourceGroup().id)}'
param databaseAdmin string = 'esmaadmin'
@secure()
param databasePassword string
@secure()
param wixApiKey string = ''
param wixSiteId string = ''
param wixCollectionId string = 'Patenhuehner'
param publicWebsiteOrigin string = 'https://www.kingkong-ev.de'

resource database 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: databaseName
  location: location
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    administratorLogin: databaseAdmin
    administratorLoginPassword: databasePassword
    version: '16'
    storage: {
      storageSizeGB: 32
      autoGrow: 'Enabled'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    network: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

resource databaseFirewall 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: database
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource databaseCatalog 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: database
  name: 'esma'
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

resource web 'Microsoft.Web/staticSites@2024-11-01' = {
  name: appName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    repositoryUrl: ''
    branch: ''
    stagingEnvironmentPolicy: 'Enabled'
    allowConfigFileUpdates: true
    enterpriseGradeCdnStatus: 'Disabled'
  }
}

resource apiSettings 'Microsoft.Web/staticSites/config@2024-11-01' = {
  parent: web
  name: 'functionappsettings'
  properties: {
    PGHOST: database.properties.fullyQualifiedDomainName
    PGPORT: '5432'
    PGUSER: '${databaseAdmin}'
    PGPASSWORD: databasePassword
    PGDATABASE: 'esma'
    PGSSLMODE: 'require'
    WIX_API_KEY: wixApiKey
    WIX_SITE_ID: wixSiteId
    WIX_COLLECTION_ID: wixCollectionId
    CORS_ORIGIN: publicWebsiteOrigin
  }
}

output staticWebAppName string = web.name
output staticWebAppUrl string = 'https://${web.properties.defaultHostname}'
output postgresqlHost string = database.properties.fullyQualifiedDomainName
