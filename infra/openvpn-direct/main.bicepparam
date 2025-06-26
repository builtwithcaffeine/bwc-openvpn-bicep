using './main.bicep'

param customerName = ''
param environmentType = 'dev'
param location = ''
param locationShortCode = ''
param deployedBy = ''

param publicIp = ''

// param virtualNetworkSettings = {

// }

param virtualMachineUserName = 'ladm_bwcadmin'

param virtualMachineUserPassword = ''
