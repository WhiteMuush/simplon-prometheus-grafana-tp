terraform {
  required_version = ">= 1.9"

  # State lives in a storage account bootstrapped by hand with az cli, inside
  # my own resource group. It cannot be created by this configuration: the
  # backend has to exist before the first init that uses it.
  #
  #   az storage account create --name stmpetittfstate --resource-group mpetitRG \
  #     --location francecentral --sku Standard_LRS --kind StorageV2 \
  #     --min-tls-version TLS1_2 --allow-blob-public-access false
  #   az storage container create --name tfstate --account-name stmpetittfstate --auth-mode key
  #
  # The cohort-wide storage account from the assignment is not usable here:
  # my account has no listKeys permission on it (403 AuthorizationFailed).
  backend "azurerm" {
    resource_group_name  = "mpetitRG"
    storage_account_name = "stmpetittfstate"
    container_name       = "tfstate"
    key                  = "monitoring-etendu.tfstate"
  }
}
