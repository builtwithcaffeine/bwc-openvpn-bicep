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
param resourceGroupName string = 'rg-x-openvpn-${customerName}-linux-${locationShortCode}'

param keyVaultName string = 'kv-${customerName}-linux-${locationShortCode}'

@description('The Network Security Group Name')
param networkSecurityGroupName string = 'nsg-${customerName}-linux-${locationShortCode}'

@description('The Virtual Network Name')
param virtualNetworkName string = 'vnet-${customerName}-linux-${locationShortCode}'

@description('The Subnet Name')
param subnetName string = 'snet-${customerName}-linux-${locationShortCode}'

@description('The Virtual Network Address Space')
param vnetAddressSpace array

@description('The Virtual Network Address Space')
param subnetAddressPrefix string

@description('The name of the virtual machine')
param vmHostName string = 'vm-linux-01'

@description('The Local User Account Name')
param vmUserName string

@description('The Local User Account Password')
@secure()
param vmUserPassword string

//
// Azure Verified Modules - No Hard Coded Values below this line!

module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.1' = {
  name: 'create-resource-group'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

module createManagedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  name: 'create-managed-identity'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'id-${vmHostName}-${environmentType}-${locationShortCode}'
    location: location
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module AssignRbacManagedIdentity 'br/public:avm/res/authorization/role-assignment/rg-scope:0.1.0' = {
  name: 'AssignRbacManagedIdentity'
  scope: resourceGroup(resourceGroupName)
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
  scope: resourceGroup(resourceGroupName)
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
    createResourceGroup
  ]
}

module createVirtualNetwork 'br/public:avm/res/network/virtual-network:0.7.0' = {
  name: 'create-virtual-network'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: virtualNetworkName
    location: location
    addressPrefixes: vnetAddressSpace
    subnets: [
      {
        name: 'snet-shared-resource'
        addressPrefix: '10.0.0.0/26'
      }
      {
        name: 'snet-compute'
        addressPrefix: '10.0.0.64/26'
        networkSecurityGroupResourceId: createNetworkSecurityGroup.outputs.resourceId
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
  scope: resourceGroup(resourceGroupName)
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

module createVirtualMachine 'br/public:avm/res/compute/virtual-machine:0.16.0' = {
  name: 'create-virtual-machine'
  scope: resourceGroup(resourceGroupName)
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
    tags: tags
  }
  dependsOn: [
    createVirtualNetwork
  ]
}

module createKeyVault 'br/public:avm/res/key-vault/vault:0.13.0' = {
  name: 'create-key-vault'
  scope: resourceGroup(resourceGroupName)
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
    AssignRbacManagedIdentity
  ]
}

