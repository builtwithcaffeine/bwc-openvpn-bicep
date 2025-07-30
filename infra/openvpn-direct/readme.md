# OpenVPN on Azure: Direct Access Setup Without Azure Firewall


## Pre Flight Checks

Clone the Github Repository

```
git clone https://azure.github.io/Azure-Verified-Modules/indexes/bicep/bicep-resource-modules/
```

### Update CloudInit Values

Ensure the Key Vault name on `Line 30: - export keyvaultName=kv-bwc-openvpn-acc-weu` is updated.

## Infrastructure Deployment

```
.\Invoke-AzDeployment.ps1 -targetScope sub -subscriptionId b67e1026-b589-41e2-b41f-73f8803f71a0 -environmentType acc -customerName bwc -location westeurope -deploy
```

The deployment creates three resources groups
 - shared
 - compute
 - web app

After this we need to create a User `appsvc_ovpn` with an SSH Key and upload that to the Key Vault.

> [!TIP]
> Ensure you have the RBAC Role: `Key Vault Secrets Officer`

```
az keyvault secret set --vault-name kv-bwc-openvpn-acc-weu  --name ssh-private-key --file sshkey-appsvc_ovpn.pem
```

and configure the App Service Environment Variables for SSH and Public IPs

Then Configure the Web App to pull from GitHub