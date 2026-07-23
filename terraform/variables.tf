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

# No default on purpose: a personal address does not belong in a public repo.
# Set it in terraform.tfvars, which .gitignore keeps out of git.
variable "alert_email" {
  description = "Address receiving the Action Group notifications."
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.alert_email))
    error_message = "alert_email must be a valid email address."
  }
}

# No default on purpose either: this is a home IP address, which locates its
# owner. Same treatment, set it in terraform.tfvars.
variable "allowed_source_ip" {
  description = "Only this address may reach SSH and the Prometheus UI on the VM. Update it when your ISP hands you a new one."
  type        = string

  validation {
    condition     = can(cidrnetmask("${var.allowed_source_ip}/32"))
    error_message = "allowed_source_ip must be a single IPv4 address."
  }
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
