variable "resource_group_name" {
  description = "Pre-created resource group. Everything is deployed inside it, nothing outside."
  type        = string
  default     = "mpetitRG"
}

variable "owner" {
  description = "Suffix appended to every resource name. Lowercase, no space: it ends up in a public DNS name."
  type        = string
  default     = "mpetit"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.owner))
    error_message = "owner must contain only lowercase letters, digits and hyphens."
  }
}

variable "location" {
  description = "Azure region. Resources inherit the resource group location, this is a fallback."
  type        = string
  default     = "francecentral"
}

variable "alert_email" {
  description = "Address receiving the Action Group notifications."
  type        = string
  default     = "you@example.com"
}

variable "ssh_public_key_path" {
  description = "Public key injected into the Prometheus VM."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    managed_by  = "terraform"
    environment = "tp"
    project     = "monitoring-etendu"
  }
}
