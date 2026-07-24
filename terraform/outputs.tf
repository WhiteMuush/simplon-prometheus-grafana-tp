##############################################################################
# Outputs referenced by docs/CONSIGNES.md and by the Makefile scripts.
##############################################################################

output "resource_group_name" {
  description = "Resource group this team is confined to."
  value       = data.azurerm_resource_group.rg.name
}

output "app_service_url" {
  description = "HTTPS URL of the log-analyser API."
  value       = "https://${azurerm_linux_web_app.app.default_hostname}"
}

output "app_insights_connection_string" {
  description = "Injected into the App Service app_settings."
  value       = azurerm_application_insights.appi.connection_string
  sensitive   = true
}

output "grafana_endpoint" {
  description = "Azure Managed Grafana URL."
  value       = azurerm_dashboard_grafana.grafana.endpoint
}

output "dce_id" {
  description = "Auto-created Data Collection Endpoint, needed to build the remote_write URL."
  value       = azurerm_monitor_workspace.amw.default_data_collection_endpoint_id
}

output "dcr_id" {
  description = "Auto-created Data Collection Rule, needed to build the remote_write URL."
  value       = azurerm_monitor_workspace.amw.default_data_collection_rule_id
}

output "prometheus_vm_public_ip" {
  description = "SSH target for the Prometheus VM."
  value       = azurerm_public_ip.pip.ip_address
}
