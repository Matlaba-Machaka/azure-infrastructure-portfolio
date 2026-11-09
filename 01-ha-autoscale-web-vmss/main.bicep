@description('Azure region for deployment')
param location string = 'southafricanorth'

@description('Admin username for the VMSS instances')
param adminUsername string = 'azureAdmin'

@description('SSH Public Key for authentication')
@secure()
param sshPublicKey string

var vnetName = 'vnet-web-01'
var subnetName = 'snet-web-01'
var nsgName = 'nsg-web-01'
var pipName = 'lb-webPublicIP'
var lbName = 'lb-web-01'
var vmssName = 'vmss-web-01'

// 1. Network Security Group (Port 80 HTTP only)
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
        }
      }
    ]
  }
}

// 2. Virtual Network & Subnet
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.10.0.0/16']
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.10.1.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

// 3. Zone-Redundant Standard Public IP for Load Balancer
resource publicIP 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: pipName
  location: location
  sku: {
    name: 'Standard'
  }
  zones: ['1', '2', '3']
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// 4. Standard Load Balancer
resource lb 'Microsoft.Network/loadBalancers@2023-09-01' = {
  name: lbName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'loadBalancerFrontEnd'
        properties: {
          publicIPAddress: {
            id: publicIP.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'bepool-web'
      }
    ]
    probes: [
      {
        name: 'http-probe'
        properties: {
          protocol: 'Tcp'
          port: 80
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'rule-http'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, 'loadBalancerFrontEnd')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, 'bepool-web')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', lbName, 'http-probe')
          }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          enableFloatingIP: false
          idleTimeoutInMinutes: 4
        }
      }
    ]
  }
}

// 5. Flexible VM Scale Set (No Public IPs on VMs)
resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2023-09-01' = {
  name: vmssName
  location: location
  sku: {
    name: 'Standard_B1s'
    tier: 'Standard'
    capacity: 2
  }
  zones: ['1', '2', '3']
  properties: {
    orchestrationMode: 'Flexible'
    platformFaultDomainCount: 1
    virtualMachineProfile: {
      storageProfile: {
        imageReference: {
          publisher: 'Canonical'
          offer: '0001-com-ubuntu-server-jammy'
          sku: '22_04-lts-gen2'
          version: 'latest'
        }
        osDisk: {
          createOption: 'FromImage'
          managedDisk: {
            storageAccountType: 'StandardSSD_LRS'
          }
        }
      }
      osProfile: {
        computerNamePrefix: 'vmss-web'
        adminUsername: adminUsername
        customData: loadFileAsBase64('cloud-init.yaml')
        linuxConfiguration: {
          disablePasswordAuthentication: true
          ssh: {
            publicKeys: [
              {
                path: '/home/${adminUsername}/.ssh/authorized_keys'
                keyData: sshPublicKey
              }
            ]
          }
        }
      }
      networkProfile: {
        networkApiVersion: '2022-11-01'
        networkInterfaceConfigurations: [
          {
            name: 'nic-web'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: 'ipconfig1'
                  properties: {
                    subnet: {
                      id: vnet.properties.subnets[0].id
                    }
                    loadBalancerBackendAddressPools: [
                      {
                        id: lb.properties.backendAddressPools[0].id
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
    }
  }
}

output loadBalancerPublicIP string = publicIP.properties.ipAddress
