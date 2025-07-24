targetScope = 'subscription'

//
// Imported Parameters

@description('Azure Location')
param location string

@description('Azure Location Short Code')
param locationShortCode string

@description('Customer Name')
param customerName string

@description('Environment Type')
param environmentType string

@description('User Deployment Name')
param deployedBy string

@description('Azure Metadata Tags')
param tags object = {
  environmentType: environmentType
  deployedBy: deployedBy
  deployedDate: utcNow('yyyy-MM-dd')
}

@description('Cloud-init configuration as a string')
@allowed([
  'cloudInit.yaml'
])
param cloudInitFile string = 'cloudInit.yaml'

var cloudInitData = loadTextContent(cloudInitFile)

// var cloudInitData = '''
// #cloud-config
// package_update: true
// package_upgrade: true
// packages:
//   - nginx

// runcmd:
//   - systemctl enable nginx
//   - systemctl start nginx

// write_files:
//   - path: /var/www/html/index.html
//     permissions: '0644'
//     content: |
//       <html>
//         <head>
//           <title>Welcome to Nginx on Ubuntu 24.04 LTS!</title>
//         </head>
//         <body>
//           <h1>It works!</h1>
//         </body>
//       </html>
// '''

//
// Bicep Deployment Variables

@description('The Resource Group Name')
param resourceGroupName array = [
  'rg-x-${customerName}-shared-resources-${environmentType}-${locationShortCode}'
  'rg-x-${customerName}-openvpn-${environmentType}-${locationShortCode}'
  'rg-x-${customerName}-openvpn-web-${environmentType}-${locationShortCode}'
]

@description('The Log Analytics Workspace Name')
param vmInsightsLogAnalyticsWorkspaceName string
param appInsightsLogAnalyticsWorkspaceName string

@description('The Data Collection Rule Name')
param linuxDataCollectionRuleName string

@description('Application Insights Name')
param appInsightsName string

@description('App Service Plan Name')
param appServicePlanName string

@description('The Key Vault Name')
param keyVaultName string

@description('The Network Security Group Name')
param networkSecurityGroupName string

@description('The Virtual Network Name')
param virtualNetworkName string

@description('The Virtual Network Address Space')
param vnetAddressSpace array

param sharedResourceAddressPrefix string
param computeAddressPrefix string
param appServiceAddressPrefix string

@description('The Virtual Machine Host name')
param vmHostName string

@description('The Local User Account Name')
param vmUserName string

@description('The Local User Account Password')
@secure()
param vmUserPassword string

//
// Azure Verified Modules - No Hard Coded Values below this line!
//

module createResourceGroups 'br/public:avm/res/resources/resource-group:0.4.1' = [for rgName in resourceGroupName: {
  name: 'create-resource-group-${rgName}'
  params: {
    name: rgName
    location: location
    tags: tags
  }
}]

// OpenVPN Virtual Machine Deployment

module createVmInsightsLogAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.9.0' = {
  name: 'create-log-analytics-workspace-vminsights'
  scope: resourceGroup(resourceGroupName[1])
  params: {
    name: vmInsightsLogAnalyticsWorkspaceName
    location: location
    skuName: 'PerGB2018'
    dataRetention: 90
  }
  dependsOn: [
    createResourceGroups
  ]
}

module createAppInsightsLogAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.9.0' = {
  name: 'create-log-analytics-workspace-appinsights'
  scope: resourceGroup(resourceGroupName[2])
  params: {
    name: appInsightsLogAnalyticsWorkspaceName
    location: location
    skuName: 'PerGB2018'
    dataRetention: 90
  }
  dependsOn: [
    createResourceGroups
  ]
}


module createManagedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  name: 'create-managed-identity'
  scope: resourceGroup(resourceGroupName[1])
  params: {
    name: 'id-${customerName}-openvpn-${environmentType}-${locationShortCode}'
    location: location
    tags: tags
  }
  dependsOn: [
    createResourceGroups
  ]
}

module AssignRbacManagedIdentityRg0 'br/public:avm/res/authorization/role-assignment/rg-scope:0.1.0' = {
  name: 'AssignRbacManagedIdentity-${resourceGroupName[0]}'
  scope: resourceGroup(resourceGroupName[0])
  params: {
    roleDefinitionIdOrName: 'Contributor'
    principalId: createManagedIdentity.outputs.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    createManagedIdentity
  ]
}

module AssignRbacManagedIdentityRg1 'br/public:avm/res/authorization/role-assignment/rg-scope:0.1.0' = {
  name: 'AssignRbacManagedIdentity-${resourceGroupName[1]}'
  scope: resourceGroup(resourceGroupName[1])
  params: {
    roleDefinitionIdOrName: 'Contributor'
    principalId: createManagedIdentity.outputs.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    createManagedIdentity
  ]  
}

module createNetworkSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.1' = {
  name: 'createNetworkSecurityGroup'
  scope: resourceGroup(resourceGroupName[1])
  params: {
    name: networkSecurityGroupName
    location: location
    securityRules: [
      {
        name: 'allowOpenVPN_UDP'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Udp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '1194'
        }
      }
    ]
    tags: tags
  }
  dependsOn: [
    createResourceGroups
  ]
}

module createVirtualNetwork 'br/public:avm/res/network/virtual-network:0.7.0' = {
  name: 'create-virtual-network'
  scope: resourceGroup(resourceGroupName[0])
  params: {
    name: virtualNetworkName
    location: location
    addressPrefixes: vnetAddressSpace
    subnets: [
      {
        name: 'snet-shared-resource-${environmentType}-${locationShortCode}'
        addressPrefix: sharedResourceAddressPrefix
      }
      {
        name: 'snet-compute-${environmentType}-${locationShortCode}'
        addressPrefix: computeAddressPrefix
        networkSecurityGroupResourceId: createNetworkSecurityGroup.outputs.resourceId
      }
      {
        name: 'snet-appservice-${environmentType}-${locationShortCode}'
        addressPrefix: appServiceAddressPrefix
        delegation: 'Microsoft.Web/serverFarms'
        serviceEndpoints: [
        'Microsoft.Storage'
        'Microsoft.Web'
        ]
      }
    ]
    tags: tags
  }
  dependsOn: [
    createNetworkSecurityGroup
  ]  
}

module createKvPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.1' = {
  name: 'create-kv-private-dns-zone'
  scope: resourceGroup(resourceGroupName[0])
  params: {
    name: 'privatelink.vaultcore.azure.net'
    virtualNetworkLinks: [
      {
        name: 'link-to-vnet-${virtualNetworkName}'
        virtualNetworkResourceId: createVirtualNetwork.outputs.resourceId
        registrationEnabled: false
      }
    ]
    tags: tags
  }
  dependsOn: [
    createVirtualNetwork
  ]
}

module createAppPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.1' = {
  name: 'create-app-private-dns-zone'
  scope: resourceGroup(resourceGroupName[0])
  params: {
    name: 'privatelink.azurewebsites.net'
    virtualNetworkLinks: [
      {
        name: 'link-to-vnet-${virtualNetworkName}'
        virtualNetworkResourceId: createVirtualNetwork.outputs.resourceId
        registrationEnabled: false
      }
    ]
    tags: tags
  }
  dependsOn: [
    createVirtualNetwork
  ]
}

module createKeyVault 'br/public:avm/res/key-vault/vault:0.13.0' = {
  name: 'create-key-vault'
  scope: resourceGroup(resourceGroupName[0])
  params: {
    name: keyVaultName
    location: location
    sku: 'standard'
    enablePurgeProtection: false
    enableRbacAuthorization: true
    publicNetworkAccess: 'Disabled'
    secrets: [
      {
        name: 'certificateAuthPassword'
        value: 'ca-awesome-password'
      }
    ]
    roleAssignments: [
      {
        principalId: createManagedIdentity.outputs.principalId
        roleDefinitionIdOrName: '/providers/Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User
      }
    ]
    privateEndpoints: [
      {
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: createKvPrivateDnsZone.outputs.resourceId
            }
          ]
        }
        service: 'vault'
        subnetResourceId: createVirtualNetwork.outputs.subnetResourceIds[0]
      }
    ]
    tags: tags
  }
  dependsOn: [
    createResourceGroups
  ]
}

module createLinuxDataCollectionRule 'br/public:avm/res/insights/data-collection-rule:0.4.2' = {
  name: 'create-linux-data-collection-rule'
  scope: resourceGroup(resourceGroupName[1])
  params: {
    name: linuxDataCollectionRuleName
    location: location
    dataCollectionRuleProperties: {
      kind: 'Linux'
      description: 'Data collection rule for VM Insights.'
      dataFlows: [
        {
          streams: [
            'Microsoft-InsightsMetrics'
          ]
          destinations: [
            createVmInsightsLogAnalyticsWorkspace.outputs.name
          ]
        }
        {
          streams: [
            'Microsoft-ServiceMap'
          ]
          destinations: [
            createVmInsightsLogAnalyticsWorkspace.outputs.name
          ]
        }
      ]
      dataSources: {
        performanceCounters: [
          {
            streams: [
              'Microsoft-InsightsMetrics'
            ]
            samplingFrequencyInSeconds: 60
            counterSpecifiers: [
              '\\VmInsights\\DetailedMetrics'
            ]
            name: 'VMInsightsPerfCounters'
          }
        ]
        extensions: [
          {
            streams: [
              'Microsoft-ServiceMap'
            ]
            extensionName: 'DependencyAgent'
            extensionSettings: {}
            name: 'DependencyAgentDataSource'
          }
        ]
      }
      destinations: {
        logAnalytics: [
          {
            workspaceResourceId: createVmInsightsLogAnalyticsWorkspace.outputs.resourceId
            workspaceId: createVmInsightsLogAnalyticsWorkspace.outputs.logAnalyticsWorkspaceId
            name: createVmInsightsLogAnalyticsWorkspace.outputs.name
          }
        ]
      }
    }
    tags: tags
  }
  dependsOn: [
    createVmInsightsLogAnalyticsWorkspace
  ]
}

module createVirtualMachine 'br/public:avm/res/compute/virtual-machine:0.16.0' = {
  name: 'create-virtual-machine'
  scope: resourceGroup(resourceGroupName[1])
  params: {
    name: vmHostName
    adminUsername: vmUserName
    adminPassword: vmUserPassword
    location: location
    osType: 'Linux'
    vmSize: 'Standard_B2ms'
    customData: cloudInitData
    availabilityZone: 1
    bootDiagnostics: true
    secureBootEnabled: true
    encryptionAtHost: true
    vTpmEnabled: true
    securityType: 'TrustedLaunch'
    managedIdentities: {
      systemAssigned: false
      userAssignedResourceIds: [
        createManagedIdentity.outputs.resourceId
      ]
    }
    imageReference: {
      publisher: 'Canonical'
      offer: 'ubuntu-24_04-lts'
      sku: 'server'
      version: 'latest'
    }
    nicConfigurations: [
      {
        ipConfigurations: [
          {
            name: 'ipconfig01'
            pipConfiguration: {
              name: '${vmHostName}-pip-01'
            }
            subnetResourceId: createVirtualNetwork.outputs.subnetResourceIds[1] // snet-compte
          }
        ]
        nicSuffix: '-nic-01'
        enableAcceleratedNetworking: false
      }
    ]
    osDisk: {
      caching: 'ReadWrite'
      diskSizeGB: 128
      managedDisk: {
        storageAccountType: 'Premium_LRS'
      }
    }
    extensionMonitoringAgentConfig: {
      dataCollectionRuleAssociations: [
        {
          dataCollectionRuleResourceId: createLinuxDataCollectionRule.outputs.resourceId
          name: 'SendMetricsToLAW'
        }
      ]
      enabled: true
      enableAutomaticUpgrade: true
    }
    tags: tags
    
  }
  dependsOn: [
    createVirtualNetwork
  ]
}



// OpenVPN Web App Deployment


module createApplicationInsights 'br/public:avm/res/insights/component:0.6.0' = {
  name: 'create-app-insights'
  scope: resourceGroup(resourceGroupName[2])
  params: {
    name: appInsightsName
    workspaceResourceId: createAppInsightsLogAnalyticsWorkspace.outputs.resourceId
    location: location
    tags: tags
  }
  dependsOn: [
    createAppInsightsLogAnalyticsWorkspace
  ]
}

module createAppServicePlan 'br/public:avm/res/web/serverfarm:0.4.1' = {
  name: 'create-app-service-plan'
  scope: resourceGroup(resourceGroupName[2])
  params: {
    name: appServicePlanName
    location: location
    kind: 'linux'
    skuName: 'B1'
    tags: tags
  }
  dependsOn: [
    createResourceGroups
  ]
}

module createAppService 'br/public:avm/res/web/site:0.16.1' = {
  name: 'create-app-service'
  scope: resourceGroup(resourceGroupName[2])
  params: {
    name: 'app-${customerName}-openvpn-web-${environmentType}-${locationShortCode}'
    location: location
    kind: 'app,linux'
    httpsOnly: true
    serverFarmResourceId: createAppServicePlan.outputs.resourceId
    virtualNetworkSubnetId: createVirtualNetwork.outputs.subnetResourceIds[2] // snet-appservice
    publicNetworkAccess: 'Enabled'
    vnetRouteAllEnabled: true
    vnetContentShareEnabled: true
    managedIdentities: {
      userAssignedResourceIds: [
        createManagedIdentity.outputs.resourceId
      ]
    }
    siteConfig: {
      linuxFxVersion: 'NODE|22-lts'
      http20Enabled: true
      minTlsVersion: '1.3'
      ftpsState: 'Disabled'
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: createApplicationInsights.outputs.connectionString
        }
        {
          name: 'APPLICATIONINSIGHTS_INSTRUMENTATIONKEY'
          value: createApplicationInsights.outputs.instrumentationKey
        }
        {
          name: 'CLIENT_ID'
          value: createManagedIdentity.outputs.clientId
        }
        {
          name: 'KEY_VAULT_NAME'
          value: createKeyVault.outputs.name
        }
        {
          name: 'SSH_USERNAME'
          value: 'appsvc_ovpn'
        }
        {
          name: 'PORT'
          value: '8000'
        }
        {
          name: 'OVPN_SERVER1_NAME'
          value: ''
        }
        {
          name: 'OVPN_SERVER1_IP_PUBLIC'
          value: ''
        }
        {
          name: 'OVPN_SERVER1_IP_PRIVATE'
          value: ''
        }
        {
          name: 'OVPN_SERVER2_NAME'
          value: ''
        }
        {
          name: 'OVPN_SERVER2_IP_PUBLIC'
          value: ''
        }
        {
          name: 'OVPN_SERVER2_IP_PRIVATE'
          value: ''
        }
        {
          name: 'OVPN_SERVER3_NAME'
          value: ''
        }
        {
          name: 'OVPN_SERVER3_IP_PUBLIC'
          value: ''
        }
        {
          name: 'OVPN_SERVER4_IP_PRIVATE'
          value: ''
        }
      ]
    }
    privateEndpoints: [
      {
        service: 'sites'
        subnetResourceId: createVirtualNetwork.outputs.subnetResourceIds[0] // snet-shared-resource
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: createAppPrivateDnsZone.outputs.resourceId
            }
          ]
        }
      }
    ]
    tags: tags
  }
  dependsOn: [
    createAppServicePlan
    createVirtualNetwork
  ]
}
