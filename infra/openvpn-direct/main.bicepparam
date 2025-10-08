using './main.bicep'

@description('Customer name for resource naming.')
param customerName = ''

@description('Azure region for deployment.')
param location = ''

@description('Short code for location.')
param locationShortCode = ''

@description('Environment type (e.g., dev, prod).')
param environmentType = ''

@description('Name of the person or system deploying resources.')
param deployedBy = ''

@description('Address space for the virtual network.')
param vnetAddressSpace = [
  '10.0.0.0/24'
]

@description('The name of the subnet to be created.')
param sharedResourceAddressPrefix = '10.0.0.0/26'
param computeAddressPrefix = '10.0.0.64/26'
param appServiceAddressPrefix = '10.0.0.128/26'

@description('The local user account name for the VM.')
param vmUserName = 'ladm_bwcadmin'

@description('The local user account password for the VM.')
@secure()
param vmUserPassword = 'P@ssw0rd123!'

@description('The Log Analytics Workspace Name')
param vmInsightsLogAnalyticsWorkspaceName = 'log-${customerName}-openvpn-vminsights-${environmentType}-${locationShortCode}'

@description('The App Insights Log Analytics Workspace Name')
param appInsightsLogAnalyticsWorkspaceName = 'log-${customerName}-openvpn-appinsights-${environmentType}-${locationShortCode}'

@description('The Data Collection Rule Name')
param linuxDataCollectionRuleName = 'MSVMI-vminsights-linux'

@description('Application Insights Name')
param appInsightsName = 'appi-${customerName}-openvpn-${environmentType}-${locationShortCode}'

@description('App Service Plan Name')
param appServicePlanName = 'asp-${customerName}-openvpn-${environmentType}-${locationShortCode}'

@description('The Key Vault Name')
param keyVaultName = 'kv-${customerName}-openvpn-${environmentType}-${locationShortCode}'

param keyVaultSecretsArray = [
      {
        name: 'ca-password'
        value: 'ca-awesome-password'
      }
    ]

@description('The Network Security Group Name')
param networkSecurityGroupName = 'nsg-${customerName}-openvpn-${environmentType}-${locationShortCode}'

@description('The Virtual Network Name')
param virtualNetworkName = 'vnet-${customerName}-openvpn-${environmentType}-${locationShortCode}'

@description('The name of the virtual machine')
param vmHostName = 'vm-linux-01-${environmentType}'
