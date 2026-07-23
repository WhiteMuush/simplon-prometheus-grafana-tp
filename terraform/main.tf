##############################################################################
# Extended monitoring stack
#
# Skeleton only: each section maps to a step of docs/CONSIGNES.md.
# Uncomment and fill in as you go, the commented blocks are there to give the
# resource order, not the answer.
##############################################################################

data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

locals {
  suffix = var.owner
  tags   = var.tags
}

##############################################################################
# Step 1: App Service hosting the log-analyser Flask API
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

##############################################################################
# Step 3: Application Insights, backed by a Log Analytics Workspace
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

##############################################################################
# Step 4.1: Azure Monitor Workspace (managed Prometheus storage)
# Creating it auto-creates a Data Collection Endpoint and Rule.
##############################################################################

resource "azurerm_monitor_workspace" "amw" {
  name                = "amw-monitoring-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
}

##############################################################################
# Step 4.2: network + VM running Prometheus
# Reuse the network module from the Terraform lab. Port 9090 from your IP only.
##############################################################################

# resource "azurerm_virtual_network" "vnet" { ... }
# resource "azurerm_subnet" "prometheus" { ... }
# resource "azurerm_network_security_group" "nsg" { ... }
# resource "azurerm_public_ip" "pip" { ... }
# resource "azurerm_network_interface" "nic" { ... }

# resource "azurerm_linux_virtual_machine" "prometheus_vm" {
#   size = "Standard_D2s_v3" # not B1s: unavailable on the training subscription
#
#   identity {
#     type = "SystemAssigned"
#   }
#
#   admin_ssh_key {
#     username   = "azureuser"
#     public_key = file(var.ssh_public_key_path)
#   }
#
#   # cloud-init must install Prometheus 3.50 or later: an empty client_id
#   # (system-assigned identity) is rejected by 2.x.
#   custom_data = base64encode(file("${path.module}/cloud-init-prometheus.sh"))
# }

##############################################################################
# Step 4.3: RBAC. Publisher writes metrics, Reader lets the VM read the
# auto-created DCE and DCR. Both are needed, propagation takes up to 30 min.
##############################################################################

# resource "azurerm_role_assignment" "prometheus_publisher" {
#   scope                = azurerm_monitor_workspace.amw.default_data_collection_rule_id
#   role_definition_name = "Monitoring Metrics Publisher"
#   principal_id         = azurerm_linux_virtual_machine.prometheus_vm.identity[0].principal_id
# }

# resource "azurerm_role_assignment" "prometheus_dce_reader" { ... }
# resource "azurerm_role_assignment" "prometheus_dcr_reader" { ... }

##############################################################################
# Step 6: Azure Managed Grafana
##############################################################################

# resource "azurerm_dashboard_grafana" "grafana" {
#   grafana_major_version = "12" # required, no default; error message lists valid values
#
#   identity {
#     type = "SystemAssigned"
#   }
# }

# resource "azurerm_role_assignment" "grafana_monitoring_reader" { ... }

##############################################################################
# Step 7: alerting, one business alert (PromQL) and one technical alert (KQL)
##############################################################################

# resource "azurerm_monitor_action_group" "ag" {
#   short_name = "alertmonit"
#
#   email_receiver {
#     name          = "formateur"
#     email_address = var.alert_email
#   }
# }

# resource "azurerm_monitor_alert_prometheus_rule_group" "alerte_erreurs" {
#   cluster_name = azurerm_monitor_workspace.amw.name
#   scopes       = [azurerm_monitor_workspace.amw.id]
#
#   rule {
#     enabled  = true
#     severity = 2
#
#     # app.py exposes log_erreurs_total as a Counter, which only ever grows.
#     # "log_erreurs_total > 5" would fire once and stay firing until the App
#     # Service restarts. Alert on the growth over a window instead, so the
#     # alert clears on its own once errors stop.
#     expression = "increase(log_erreurs_total[5m]) > 5"
#
#     action {
#       action_group_id = azurerm_monitor_action_group.ag.id
#     }
#   }
# }
# resource "azurerm_monitor_scheduled_query_rules_alert_v2" "alerte_taux_erreur" { ... }
