##############################################################################
# App Service hosting the log-analyser Flask API.
##############################################################################

resource "azurerm_service_plan" "plan" {
  name                = "plan-monitoring-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = "B1"
  tags                = local.tags
}

resource "azurerm_linux_web_app" "app" {
  name                = "app-monitoring-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  service_plan_id     = azurerm_service_plan.plan.id
  tags                = local.tags
  site_config {
    application_stack {
      python_version = "3.11"
    }
    # Do NOT set app_command_line: it breaks Azure's Flask autodetection.
  }
  app_settings = {
    "SCM_DO_BUILD_DURING_DEPLOYMENT"        = "true"
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.appi.connection_string
  }
}
