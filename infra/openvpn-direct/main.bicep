targetScope = 'subscription'

// Parameters Imported from Invoke-AzDeployment.ps1

@description('Customer Name')
param customerName string

@description('Environment Type')
@allowed(['dev', 'acc', 'prod'])
param environmentType string

param location string

@description('Location Short Code')
param locationShortCode string

@description('Deployed By')
param deployedBy string

@description('Azure Tags')
param tags object = {
  deployedBy: deployedBy
  deployedOn: utcNow('yyyy-MM-dd')
  Environment: environmentType
}

var cloudInit = base64(loadTextContent('openvpn.yaml'))

//

@description('Resource Group Name')
param resourceGroupName string = 'rg-x-${customerName}-openvpn-${environmentType}-${locationShortCode}'

@description('Network Security Group Name')
param networkSecurityGroupName string = 'nsg-${customerName}-openvpn-${environmentType}-${locationShortCode}'

@description('Public IP Address')
param publicIp string

@description('Virtual Network Name')
param virtualNetworkName string = 'vnet-${customerName}-openvpn-${environmentType}-${locationShortCode}'

param routeTableName string = 'rt-openvpn'

//@description('Virtual Network Settings')
//param virtualNetworkSettings object

@description('Virtual Machine Name')
param virtualMachineName string = 'vm-${customerName}-openvpn-${environmentType}-${locationShortCode}'

@description('Virtual Machine User Name')
param virtualMachineUserName string

@secure()
@description('Virtual Machine User Password')
param virtualMachineUserPassword string

//
// No Hard Code Values
//

module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.1' = {
  name: 'createResourceGroup'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

module createRouteTable 'br/public:avm/res/network/route-table:0.4.1' = {
  name: 'routeTableDeployment'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: routeTableName
  }
  dependsOn: [
    createResourceGroup
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
        name: 'ALLOW_OPENVPN_UDP'
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
      {
        name: 'ALLOW_OPENSSH_TCP'
        properties: {
          priority: 101
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: publicIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
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
  name: 'createVirtualNetwork'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: virtualNetworkName
    location: location
    addressPrefixes: [
      '10.0.0.0/16'
    ]
    subnets: [
      {
        name: 'default'
        addressPrefix: '10.0.1.0/24'
        networkSecurityGroupResourceId: createNetworkSecurityGroup.outputs.resourceId
      }
    ]
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createVirtualMachine 'br/public:avm/res/compute/virtual-machine:0.15.0' = {
  name: 'createVirtualMachine'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: virtualMachineName
    adminUsername: virtualMachineUserName
    adminPassword: virtualMachineUserPassword
    location: location
    osType: 'Linux'
    vmSize: 'Standard_B1ls' // vcpu cores: 1, memory: 0.5 GB
    zone: 0
    bootDiagnostics: true
    secureBootEnabled: true
    vTpmEnabled: true
    securityType: 'TrustedLaunch'
    imageReference: {
      publisher: 'Canonical'
      offer: 'ubuntu-24_04-lts'
      sku: 'server'
      version: 'latest'
    }
    nicConfigurations: [
      {
        enableIPForwarding: true
        ipConfigurations: [
          {
            name: 'ipconfig01'
            pipConfiguration: {
              name: '${virtualMachineName}-pip-01'
            }
            subnetResourceId: createVirtualNetwork.outputs.subnetResourceIds[0]
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
  }
  dependsOn: [
    createVirtualNetwork
  ]
}
