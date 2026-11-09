ssh-keygen -t rsa -b 4096

az group create --name rg-proj1-ha-vmss --location southafricanorth

az deployment group create `
   --resource-group rg-proj1-ha-vmss `
   --template-file main.bicep `
   --parameters sshPublicKey="$(Get-Content ~/.ssh/id_rsa.pub)"




