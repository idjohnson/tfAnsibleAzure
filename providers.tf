terraform {
  required_version = ">=0.12"

  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~>1.5"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.48.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.0"
    }
    tls = {
      source = "hashicorp/tls"
      version = "~>4.0"
    }
  }
}

provider "azurerm" {
  features {}
  
  tenant_id       = "28c575f6-ade1-4838-8e7c-7e6d1ba0eb4a"
  subscription_id = "d955c0ba-13dc-44cf-a29a-8fed74cbb22d"
}