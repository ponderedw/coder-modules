terraform {
  required_version = ">= 1.3"
  required_providers {
    coder = {
      source = "coder/coder"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# docker-dev — Docker Engine installation for Coder workspaces (Ubuntu/Debian).
#
# Outputs:
#   startup_script — bash snippet for coder_agent startup_script
# ─────────────────────────────────────────────────────────────────────────────

variable "docker_user" {
  type        = string
  default     = "coder"
  description = "OS user to add to the docker group."
}

variable "start_service" {
  type        = bool
  default     = true
  description = "Start the Docker daemon after install."
}

locals {
  config = {
    docker_user   = var.docker_user
    start_service = var.start_service
  }
}

output "startup_script" {
  description = "Bash snippet to interpolate into the template's coder_agent startup_script."
  value = templatefile("${path.module}/docker-dev.sh", {
    config_b64 = base64encode(jsonencode(local.config))
  })
}
