##############################################################################
# Alerting: one business alert (PromQL) and one technical alert (KQL).
##############################################################################

resource "azurerm_monitor_action_group" "ag" {
  name                = "ag-monitoring-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.rg.name
  short_name          = "alertmonit"

  email_receiver {
    name          = "owner"
    email_address = var.alert_email
  }
}

resource "azurerm_monitor_alert_prometheus_rule_group" "alerte_erreurs" {
  name                = "alerte-erreurs-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  scopes              = [azurerm_monitor_workspace.amw.id]

  # Second switch, distinct from the "enabled" inside the rule block below.
  # Without it the provider sends false, so Azure holds an enabled rule inside
  # a disabled group and never evaluates the expression: no alert, no email,
  # and nothing in the portal explaining why.
  rule_group_enabled = true

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
