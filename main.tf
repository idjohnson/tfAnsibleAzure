# Create a resource group
resource "azurerm_resource_group" "rg" {
  name     = "idj-east-rg"
  location = "East US"
}

# Create a virtual network within the resource group
resource "azurerm_virtual_network" "examplevnet" {
  name                = "example-network"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.0.0.0/16"]
}

# Create subnet
resource "azurerm_subnet" "my_terraform_subnet" {
  name                 = "mySubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.examplevnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create public IPs
resource "azurerm_public_ip" "my_terraform_public_ip" {
  name                = "myPublicIP"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "my_terraform_nsg" {
  name                = "myNetworkSecurityGroup"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Create network interface
resource "azurerm_network_interface" "my_terraform_nic" {
  name                = "myNIC"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "my_nic_configuration"
    subnet_id                     = azurerm_subnet.my_terraform_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.my_terraform_public_ip.id
  }
}

# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "example" {
  network_interface_id      = azurerm_network_interface.my_terraform_nic.id
  network_security_group_id = azurerm_network_security_group.my_terraform_nsg.id
}

# Generate random text for a unique storage account name
resource "random_id" "random_id" {
  keepers = {
    # Generate a new ID only when a new resource group is defined
    resource_group = azurerm_resource_group.rg.name
  }

  byte_length = 8
}

# Create storage account for boot diagnostics
resource "azurerm_storage_account" "my_storage_account" {
  name                     = "diag${random_id.random_id.hex}"
  location                 = azurerm_resource_group.rg.location
  resource_group_name      = azurerm_resource_group.rg.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Create (and display) an SSH key
resource "tls_private_key" "example_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "idrsa" {
  filename = "./id_rsa"
  file_permission = "0600"
  content  = <<-EOT
    ${tls_private_key.example_ssh.private_key_pem}
  EOT
}

resource "local_file" "idrsapub" {
  filename = "./id_rsa.pub"
  file_permission = "0633"
  content  = <<-EOT
    ${tls_private_key.example_ssh.public_key_openssh}
  EOT
}

# Fetching an AKV Secret

data "azurerm_key_vault" "idjakv" {
  name                = "idjakv"
  resource_group_name = "idjakvrg"
}

data "azurerm_key_vault_secret" "ghpassword" {
  name         = "GithubToken-MyFull90d"
  key_vault_id = data.azurerm_key_vault.idjakv.id
}

resource "azurerm_key_vault_secret" "idjrsapubsecret" {
  name         = "azure-myvm-pub"
  value        = tls_private_key.example_ssh.public_key_openssh
  key_vault_id = data.azurerm_key_vault.idjakv.id
}

resource "azurerm_key_vault_secret" "idjrsaprivsecret" {
  name         = "azure-myvm-priv"
  value        = tls_private_key.example_ssh.private_key_pem
  key_vault_id = data.azurerm_key_vault.idjakv.id
}

#pull the code from github
/*
resource "null_resource" "git_clone" {
  provisioner "local-exec" {
    command = "git clone https://idjohnson:${data.azurerm_key_vault_secret.ghpassword.value}@github.com/idjohnson/ansible-playbooks ./local_co"
  }
}
*/

# Create virtual machine

resource "azurerm_linux_virtual_machine" "my_terraform_vm" {
  name                  = "myVM"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.my_terraform_nic.id]
  size                  = "Standard_DS1_v2"

  os_disk {
    name                 = "myOsDisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  computer_name                   = "myvm"
  admin_username                  = "azureuser"
  disable_password_authentication = true

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.example_ssh.public_key_openssh
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.my_storage_account.primary_blob_endpoint
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-add-repository -y ppa:ansible/ansible", 
      "sudo apt update",
      "sudo apt install python3 build-essential ansible -y", 
      "git clone https://github.com/idjohnson/ansible-playbooks ./local_co",
      "echo '[all]' > myhosts.ini",
      "echo 'localhost' >> myhosts.ini",
      "ansible-playbook -i myhosts.ini --connection=local ./local_co/cloudcustodiandocker.yaml",      
      "echo Done!"
    ]

    connection {
      host        = azurerm_linux_virtual_machine.my_terraform_vm.public_ip_address
      type        = "ssh"
      user        = "azureuser"
      private_key = tls_private_key.example_ssh.private_key_pem
    }
  }

  // depends_on = [ null_resource.git_clone ]
}

# AKS


resource "random_pet" "azurerm_kubernetes_cluster_name" {
  prefix = "cluster"
}

resource "random_pet" "azurerm_kubernetes_cluster_dns_prefix" {
  prefix = "dns"
}

resource "azurerm_kubernetes_cluster" "k8s" {
  location            = azurerm_resource_group.rg.location
  name                = random_pet.azurerm_kubernetes_cluster_name.id
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = random_pet.azurerm_kubernetes_cluster_dns_prefix.id
  kubernetes_version  = var.kubernetes_version

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name       = "agentpool"
    vm_size    = "Standard_D2_v2"
    node_count = var.node_count
  }
  linux_profile {
    admin_username = "ubuntu"

    ssh_key {
      key_data = jsondecode(azapi_resource_action.ssh_public_key_gen.output).publicKey
    }
  }
  network_profile {
    network_plugin    = "kubenet"
    load_balancer_sku = "standard"
  }
}