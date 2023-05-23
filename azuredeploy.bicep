@description('Blob storage for incoming CSV files')
param blobStorageAccountName string = ''

@description('SQL server name')
param sqlservername string = ''

@description('SQL Server - Admin user name')
param sqlAdminName string = 'sqladmin'

@description('SQL Server - Admin password')
@secure()
param sqlAdminPassword string

@description('Here are all password safed for the database and the blob storage')
param keyVaultName string  = ''

@description('Data factory name')
param datafactoryname string  = ''

@description('The location of the deployment')
param location string = resourceGroup().location

@description('Location for scripts etc.')
param _artifactsLocation string = deployment().properties.templateLink.uri 

var uniqueHostPrefix = 'k${uniqueString(resourceGroup().id)}'

param currentDateMarker string = utcNow('yyyy-MM-dd--HH-mm-ss')

var names = {
  triggerJoinChar: '|'
  resources: {
    // keyVault: empty(deploymentName) ? keyVaultName : uniqueHostPrefix // This would allow to remove the `useDerivedNames` parameter
    keyVault: empty(keyVaultName) ? uniqueHostPrefix : uniqueHostPrefix
    blobStorageAccount: empty(blobStorageAccountName) ? uniqueHostPrefix : blobStorageAccountName
    dataFactory:  empty(datafactoryname) ? uniqueHostPrefix : datafactoryname
    sql: {
      serverName: empty(sqlservername) ? uniqueHostPrefix : sqlservername
      databasename: 'database'
      administratorName: sqlAdminName
      administratorPassword: sqlAdminPassword
    }
    uami: '${uniqueHostPrefix}-runtime'
  }
  secrets:  {
    blobStorageConnectionString: 'blobStorageConnectionString'
    dataBaseConnectionString: 'databaseConnectionString'
  }
  deploymentScript: {
    name: 'deploymentScriptTriggers--${currentDateMarker}'
    azCliVersion: '2.36.0'
    scriptName: 'scripts/start-triggers.sh'
  }
  dataFactory: {
    linkedServices: {
      keyVault:    'linkedService_KeyVault'
      blobStorage: 'linkedService_BlobStorage'
      sqlDatabase: 'linkedService_Database'
    }
  }
  csvSettings: {
    expectedPrefix: 'import'
    expextedSuffix: '.csv'
  }
  roles: {
    DataFactoryContributor: '673868aa-7521-48a0-acc6-0f60742d39f5'
    KeyVault: {
      CryptoOfficer: '14b46e9e-c2b7-41b4-b07b-48a6ebf60603'
      SecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
    }
    StorageBlob: {
      DataReader: '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
    }
  }
}

var integrations = [
  {
    suffix: 'SomeSuffic'
    container: 'inputcontainer1'
    schema: {
      csv: [
        { name: 'DATE',                  type: 'String' }
        { name: 'NAME',                  type: 'String' }
        { name: 'STREET',                type: 'String' }
      ]
      db: [
        { name: 'TupleID',              type: 'int', precision: 10 }
        { name: 'DATE',                 type: 'String' }
        { name: 'NAME',                 type: 'String' }
        { name: 'STREET',               type: 'String' }
      ]
    }
  }
]

@description('A user-assigned managed identity for the runtime.')
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: names.resources.uami
  location: location
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: names.resources.blobStorageAccount
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Cool'
    allowSharedKeyAccess: true
    allowBlobPublicAccess: false
  }
}

resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2022-09-01' = {
  parent: storageAccount
  name: 'default'
}

resource sqlServer 'Microsoft.Sql/servers@2021-11-01' = {
  name: names.resources.sql.serverName
  location: location
  properties: {
    administratorLogin: names.resources.sql.administratorName
    administratorLoginPassword: names.resources.sql.administratorPassword
  }
}

resource sqlServerDatabase 'Microsoft.Sql/servers/databases@2021-11-01' = {
  parent: sqlServer, name: names.resources.sql.databasename
  location: location
  properties: {
    collation: 'Latin1_General_CI_AS'
  }
  sku: {
    name: 'Standard'
    size: 'Standard'
    tier: 'Standard'
  }
}

resource sqlServerFirewallRulesAzureInternalServices 'Microsoft.Sql/servers/firewallRules@2021-11-01' = {
  parent: sqlServer
  name: 'firewallrules'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: names.resources.keyVault
  location: location
  properties: {
    sku: { family: 'A', name: 'standard' }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
  }
}

resource uamiIsKeyVaultSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(uami.id, names.roles.KeyVault.SecretsUser, keyVault.id)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', names.roles.KeyVault.SecretsUser)
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource blobStorageConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: keyVault, name: names.secrets.blobStorageConnectionString
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value}'
  }
}

resource databaseConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01'={
  parent: keyVault 
  name: names.secrets.dataBaseConnectionString
  properties: {
    value: 'Server=tcp:${sqlServer.name}${environment().suffixes.sqlServerHostname},1433;Initial Catalog=${sqlServerDatabase.name};Persist Security Info=False;User ID=${names.resources.sql.administratorName};Password=${names.resources.sql.administratorPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
    //value: 'Server=tcp:${sqlServer.name}${environment().suffixes.sqlServerHostname},1433;Database=myDataBase;User ID=${names.resources.sql.administratorName};Password=${names.resources.sql.administratorPassword};Trusted_Connection=False;Encrypt=True;'
  }
}

resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: names.resources.dataFactory
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { 
      '${uami.id}': {}
    }
  }
}

resource uamiIsDataFactoryContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  // The UAMI must be able to call the trigger start function.
  name: guid(uami.id, names.roles.DataFactoryContributor, dataFactory.id)
  scope: dataFactory
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', names.roles.DataFactoryContributor)
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource dataFactoryLinkedServiceKeyVault 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  parent: dataFactory, name: names.dataFactory.linkedServices.keyVault
  properties: {
    type: 'AzureKeyVault'
    typeProperties: {
      baseUrl: keyVault.properties.vaultUri
    }
  }
}

resource dataFactoryLinkedServiceBlobStorage 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  parent: dataFactory, name: names.dataFactory.linkedServices.blobStorage
  properties: {
    type: 'AzureBlobStorage'
    typeProperties: {
      connectionString: {
        type: 'AzureKeyVaultSecret'
        store: {
          referenceName: dataFactoryLinkedServiceKeyVault.name
          type: 'LinkedServiceReference'
        }
        secretName: blobStorageConnectionStringSecret.name
      }
    }
  }
}

resource dataFactoryLinkedServiceDatabase 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  parent: dataFactory
  name: names.dataFactory.linkedServices.sqlDatabase
  properties: {
    type: 'AzureSqlDatabase'
    typeProperties: {
      connectionString: {
        type: 'AzureKeyVaultSecret'
        store: {
          type: 'LinkedServiceReference'
          referenceName: dataFactoryLinkedServiceKeyVault.name
        }
        secretName: databaseConnectionStringSecret.name
      }
    }
  }
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-05-01' = [for i in range(0, length(integrations)): {
  parent: blobServices
  name: toLower(integrations[i].suffix)
}]

resource uamiIsBlobDataReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for i in range(0, length(integrations)): {
  name: guid(uami.id, names.roles.KeyVault.SecretsUser, container[i].id)
  scope: container[i]
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', names.roles.StorageBlob.DataReader)
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}]

resource datasetStorage 'Microsoft.DataFactory/factories/datasets@2018-06-01' = [for i in range(0, length(integrations)): {
  parent: dataFactory, name: 'blob_${integrations[i].suffix}'
  properties: {
    type: 'DelimitedText'
    linkedServiceName: {
      referenceName: dataFactoryLinkedServiceBlobStorage.name
      type: 'LinkedServiceReference'
    }
    parameters: {
      DirectoryNameFromPipelineToDataSet: { type: 'string' }
      FileNameFromPipelineToDataSet: { type: 'string' }
    }
    typeProperties: {
      location: {
        type: 'AzureBlobStorageLocation'
        container: { type: 'Expression', value: '@dataset().DirectoryNameFromPipelineToDataSet' }
        folderPath: null
        fileName: { type: 'Expression', value: '@dataset().FileNameFromPipelineToDataSet' }
      }
      columnDelimiter: ';'
      // escapeChar: '\\'
      firstRowAsHeader: true
      encodingName: 'ISO-8859-1'
      quoteChar: '"'
    }
    schema: integrations[i].schema.csv
  }
}]

resource datasetDatabase 'Microsoft.DataFactory/factories/datasets@2018-06-01' = [for i in range(0, length(integrations)): {
  parent: dataFactory, name: 'sql_${integrations[i].suffix}'
  properties: {
    type: 'AzureSqlTable'
    linkedServiceName: {
      referenceName: dataFactoryLinkedServiceDatabase.name
      type: 'LinkedServiceReference'
    }
    typeProperties: {
      schema: 'dbo'
      table: toLower(integrations[i].suffix)
    }
    schema: integrations[i].schema.db 
  }
}]

resource pipeline 'Microsoft.DataFactory/factories/pipelines@2018-06-01' = [for i in range(0, length(integrations)): {
  parent: dataFactory, name: integrations[i].suffix
  properties: {
    parameters: {
      DirectoryNameFromTriggerToPipeline: { type: 'string' }
      FileNameFromTriggerToPipeline: { type: 'string' }
    }
    activities: [
      {
        type: 'Copy'
        name: 'Copy ${integrations[i].suffix} data'
        description: 'Pipeline copies CSV data from blob storage to SQL table'
        typeProperties: {
          source: {
            type: 'DelimitedTextSource'
            storeSettings: {
              type: 'AzureBlobStorageReadSettings'
              recursive: true 
              enablePartitionDiscovery: false
            }
            formatSettings: {
              type: 'DelimitedTextReadSettings'
            }
          }
          sink: {
            type: 'AzureSqlSink'
            writeBehavior: 'insert'
            sqlWriterUseTableLock: false
            tableOption: 'autoCreate'
            disableMetricsCollection: false
          }
          enableStaging: false 
          translator: {
            type: 'TabularTranslator'
            typeConversion: true 
            typeConversationSettings: {
              allowDataTruncation: true 
              treatBooleanAsNumber: false 
            }
          }
        }
        inputs: [
          {
            type: 'DatasetReference'
            referenceName: datasetStorage[i].name
            parameters: {
              DirectoryNameFromPipelineToDataSet: { type: 'Expression', value: '@pipeline().parameters.DirectoryNameFromTriggerToPipeline' }
              FileNameFromPipelineToDataSet: { type: 'Expression', value: '@pipeline().parameters.FileNameFromTriggerToPipeline' }
            }
          }
        ]
        outputs: [
          {
            type: 'DatasetReference'
            referenceName: datasetDatabase[i].name
          }
        ]
      }
    ]
  }
}]

resource trigger 'Microsoft.DataFactory/factories/triggers@2018-06-01' = [for i in range(0, length(integrations)): {
  parent: dataFactory
  name: integrations[i].suffix
  properties: {
    type: 'BlobEventsTrigger'
    typeProperties: {
      events: [ 'Microsoft.Storage.BlobCreated' ]
      // substring(x, lastIndexOf(x, '/') + 1, length(x) - lastIndexOf(x, '/') - 1)
      // Given 'storage/default/containername' returns 'containername'
      blobPathBeginsWith: '/${substring(container[i].name, lastIndexOf(container[i].name, '/') + 1, length(container[i].name) - lastIndexOf(container[i].name, '/') - 1)}/blobs/${names.csvSettings.expectedPrefix}'
      blobPathEndsWith: names.csvSettings.expextedSuffix
      ignoreEmptyBlobs: false
      scope: storageAccount.id
    }
    pipelines: [
      {
        pipelineReference: {
          type: 'PipelineReference'
          referenceName: pipeline[i].name
        }
        parameters: {
          DirectoryNameFromTriggerToPipeline: '@triggerBody().folderPath'
          FileNameFromTriggerToPipeline: '@triggerBody().fileName'
        }
      }
    ]
  }
}]

resource deploymentScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: names.deploymentScript.name
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { 
      '${uami.id}': {}
    }
  }
  properties: {
    azCliVersion: names.deploymentScript.azCliVersion
    timeout: 'PT10M'
    retentionInterval: 'P1D'
    cleanupPreference: 'OnExpiration'
    containerSettings: {
      containerGroupName: uniqueString(resourceGroup().id, names.deploymentScript.name)
    }
    primaryScriptUri: uri(_artifactsLocation, names.deploymentScript.scriptName)
    environmentVariables: [
      { name: 'DATAFACTORY_ID', value: dataFactory.id }
      { name: 'TRIGGERS', value: join(map(integrations, i => i.suffix), names.triggerJoinChar) }
      { name: 'TRIGGERJOINCHAR', value: names.triggerJoinChar }
    ]
  }
}

output results object = {
  containers: map(integrations, i => '${storageAccount.properties.primaryEndpoints.blob}/${i.container}')
  DATAFACTORY_ID:  dataFactory.id
  storageAccount: storageAccount.properties.primaryEndpoints.blob
}
