##############################################################################
# Azure Managed Grafana and the role assignments it needs.
##############################################################################

resource "azurerm_dashboard_grafana" "grafana" {
  # Max 23 characters, unlike every other resource here: "grafana-monitoring-mpetit"
  # is 25 and gets rejected at plan time.
  name                = "grafana-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  tags                = local.tags

  # Required, there is no default value. If "12" is rejected, the terraform
  # apply error message lists the versions currently accepted.
  grafana_major_version = "12"

  identity {
    type = "SystemAssigned"
  }

  # Without this, Grafana only ships the out-of-the-box "Azure Monitor" data
  # source, which covers KQL but not PromQL. Linking the workspace makes Azure
  # provision a Prometheus data source pointing at its query endpoint.
  azure_monitor_workspace_integrations {
    resource_id = azurerm_monitor_workspace.amw.id
  }
}

resource "azurerm_role_assignment" "grafana_monitoring_reader" {
  scope                = data.azurerm_resource_group.rg.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_dashboard_grafana.grafana.identity[0].principal_id
}

# Monitoring Reader covers the Log Analytics side. Querying Prometheus data
# out of the Azure Monitor Workspace is a separate, data-plane permission.
resource "azurerm_role_assignment" "grafana_amw_data_reader" {
  scope                = azurerm_monitor_workspace.amw.id
  role_definition_name = "Monitoring Data Reader"
  principal_id         = azurerm_dashboard_grafana.grafana.identity[0].principal_id
}

# Creating the Grafana instance grants no access to it. Without this, opening
# the endpoint returns a "you do not have access" page.
resource "azurerm_role_assignment" "grafana_admin_me" {
  scope                = azurerm_dashboard_grafana.grafana.id
  role_definition_name = "Grafana Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}
