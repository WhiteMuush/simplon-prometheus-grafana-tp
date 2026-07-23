# Copy to terraform.tfvars and fill in. *.tfvars is gitignored, this example is
# the only one whitelisted, so never put real values here.
#
#   cp example.tfvars terraform.tfvars

# Address the Action Group notifies. Personal address: keep it out of git.
alert_email = "you@example.com"

# Your current public IP. It is the only one allowed to reach SSH and the
# Prometheus UI on the VM. Find it with: curl -s ifconfig.me
allowed_source_ip = "203.0.113.10"

# Optional, these already have sensible defaults in variables.tf.
# resource_group_name = "mpetitRG"
# owner               = "mpetit"
# ssh_public_key_path = "~/.ssh/id_rsa.pub"
