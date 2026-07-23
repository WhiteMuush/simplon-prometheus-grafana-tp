variable "groupe" {
  description = "Team identifier, used as a suffix on every resource name."
  type        = string

  validation {
    condition     = contains(["groupe1", "groupe2", "groupe3"], var.groupe)
    error_message = "groupe must be one of: groupe1, groupe2, groupe3."
  }
}

variable "location" {
  description = "Azure region. Kept as a variable, but resources inherit the resource group location by default."
  type        = string
  default     = "francecentral"
}

variable "alert_email" {
  description = "Address receiving the Action Group notifications."
  type        = string
  default     = "formateur@simplon.co"
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
