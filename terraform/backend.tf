terraform {
  required_version = ">= 1.9"

  # Storage account and container are shared by the whole cohort.
  # Only "key" isolates this team's state: double-check it before the first init.
  backend "azurerm" {
    resource_group_name  = "rg-tfstate-formation"
    storage_account_name = "ststateformationdevops"
    container_name       = "tfstate"
    key                  = "monitoring-etendu-groupe1.tfstate"
  }
}
