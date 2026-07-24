##############################################################################
# Application Insights (backed by a Log Analytics Workspace) and the
# Azure Monitor Workspace that stores the managed Prometheus metrics.
##############################################################################

resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-monitoring-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

resource "azurerm_application_insights" "appi" {
  name                = "appi-monitoring-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  workspace_id        = azurerm_log_analytics_workspace.law.id
  application_type    = "web"
  tags                = local.tags
}

# Creating it auto-creates a Data Collection Endpoint and Rule.
resource "azurerm_monitor_workspace" "amw" {
  name                = "amw-monitoring-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
}
