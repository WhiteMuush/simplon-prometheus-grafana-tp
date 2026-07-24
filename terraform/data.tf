data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

# Who is running terraform: used to grant myself access to Grafana.
data "azurerm_client_config" "current" {}
