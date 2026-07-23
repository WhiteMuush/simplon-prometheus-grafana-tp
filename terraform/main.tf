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

# Who is running terraform: used to grant myself access to Grafana.
data "azurerm_client_config" "current" {}

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

# The address space the VM lives in. Nothing else uses it, but a VM cannot
# exist without a subnet, and a subnet cannot exist without a virtual network.
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-monitoring-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  address_space       = ["10.0.0.0/16"]
  tags                = local.tags
}

# A slice of the address space, reserved for Prometheus.
resource "azurerm_subnet" "prometheus" {
  name                 = "snet-prometheus"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.3.0/24"]
}

# Firewall. Azure denies inbound traffic by default, so only the two ports
# below are reachable, and only from my own address.
resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-prometheus-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  tags                = local.tags

  security_rule {
    name                       = "allow-ssh-from-me"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.allowed_source_ip
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-prometheus-ui-from-me"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9090"
    source_address_prefix      = var.allowed_source_ip
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "prometheus" {
  subnet_id                 = azurerm_subnet.prometheus.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# Static, so the address survives a VM restart and stays valid in the NSG
# rules and in my ssh config.
resource "azurerm_public_ip" "pip" {
  name                = "pip-prometheus-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

# The virtual network card: it holds the private address inside the subnet
# and carries the public IP. The VM plugs into this, not into the subnet.
resource "azurerm_network_interface" "nic" {
  name                = "nic-prometheus-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  tags                = local.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.prometheus.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_linux_virtual_machine" "prometheus_vm" {
  name                = "vm-prometheus-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  size                = "Standard_D2s_v3"
  admin_username      = "azureuser"

  identity {
    type = "SystemAssigned"
  }

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  network_interface_ids = [azurerm_network_interface.nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  custom_data = base64encode(<<-EOF
    #!/bin/bash
    # Version 3.12.0, NOT 2.53.0: a SYSTEM-assigned managed identity (our case, empty
    # client_id in prometheus.yml at step 5) requires Prometheus 3.50+ per Microsoft docs.
    # On an older version Prometheus fails at startup with "must provide an Azure Managed
    # Identity client_id in the Azure AD config".
    apt-get update
    apt-get install -y wget
    useradd --no-create-home --shell /bin/false prometheus
    wget https://github.com/prometheus/prometheus/releases/download/v3.12.0/prometheus-3.12.0.linux-amd64.tar.gz
    tar xvf prometheus-3.12.0.linux-amd64.tar.gz
    cp prometheus-3.12.0.linux-amd64/prometheus /usr/local/bin/
    mkdir -p /etc/prometheus
  EOF
  )
}

##############################################################################
# Step 4.3: RBAC. Publisher writes metrics, Reader lets the VM read the
# auto-created DCE and DCR. Both are needed, propagation takes up to 30 min.
##############################################################################

resource "azurerm_role_assignment" "prometheus_publisher" {
  scope                = azurerm_monitor_workspace.amw.default_data_collection_rule_id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_linux_virtual_machine.prometheus_vm.identity[0].principal_id
}

resource "azurerm_role_assignment" "prometheus_dce_reader" {
  scope                = azurerm_monitor_workspace.amw.default_data_collection_endpoint_id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_linux_virtual_machine.prometheus_vm.identity[0].principal_id
}

resource "azurerm_role_assignment" "prometheus_dcr_reader" {
  scope                = azurerm_monitor_workspace.amw.default_data_collection_rule_id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_linux_virtual_machine.prometheus_vm.identity[0].principal_id
}

##############################################################################
# Step 6: Azure Managed Grafana
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

##############################################################################
# Step 7: alerting, one business alert (PromQL) and one technical alert (KQL)
##############################################################################

resource "azurerm_monitor_action_group" "ag" {
  name                = "ag-monitoring-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.rg.name
  short_name          = "alertmonit"

  email_receiver {
    name          = "melvin_petiit"
    email_address = "melvin.petit31@gmail.com"
  }
}

resource "azurerm_monitor_alert_prometheus_rule_group" "alerte_erreurs" {
  name                = "alerte-erreurs-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  scopes              = [azurerm_monitor_workspace.amw.id]

  # cluster_name is deliberately absent. Azure uses it to restrict evaluation
  # to series carrying a matching "cluster" label, which the AKS addon adds on
  # its own. Nothing adds it here: our series only carry job and instance, so
  # setting cluster_name = amw-monitoring-mpetit made the rule evaluate over an
  # empty set and never fire, while the query itself was correct.
  #
  # The alternative, closer to what AKS does, is to keep cluster_name and have
  # Prometheus stamp the label itself:
  #   global:
  #     external_labels:
  #       cluster: amw-monitoring-mpetit

  rule {
    enabled = true

    # A rule is either a recording rule (record) or an alerting rule (alert).
    # This one alerts, so it needs a name to be raised under.
    alert = "TropDErreursApplicatives"

    # log_erreurs_total is a Counter, it only ever grows. A plain threshold
    # would fire once and never clear until the App Service restarts, so
    # alert on the growth over a window instead.
    expression = "increase(log_erreurs_total[5m]) > 5"
    severity   = 2
    for        = "PT1M"

    annotations = {
      summary = "More than 5 application errors in the last 5 minutes"
    }

    action {
      action_group_id = azurerm_monitor_action_group.ag.id
    }
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "alerte_taux_erreur" {
  name                 = "alerte-taux-erreur-${local.suffix}"
  resource_group_name  = data.azurerm_resource_group.rg.name
  location             = data.azurerm_resource_group.rg.location
  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"
  scopes               = [azurerm_application_insights.appi.id]
  severity             = 2

  criteria {
    query                   = "requests | where success == false"
    time_aggregation_method = "Count"
    threshold               = 5
    operator                = "GreaterThan"
  }

  action {
    action_groups = [azurerm_monitor_action_group.ag.id]
  }
}
