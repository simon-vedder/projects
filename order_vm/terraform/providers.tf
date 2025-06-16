terraform {
  required_version = ">=1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
    azuread = { #for Entra Role - UPN Validation
      source  = "hashicorp/azuread"
      version = "2.41.0"
    }
    azapi = { #for api connection
      source  = "azure/azapi"
      version = ">=0.1.0"
    }
  }
}

provider "azurerm" {
  features {}
}