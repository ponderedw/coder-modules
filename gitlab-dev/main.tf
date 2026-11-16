terraform {
  required_version = ">= 1.3"
  required_providers {
    coder = {
      source = "coder/coder"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# gitlab-dev — GitLab repo management + git tooling for Coder workspaces.
#
# Outputs:
#   startup_script     — bash snippet for coder_agent startup_script
#   extensions         — list of VS Code extension IDs (pass to code-server)
#   extensions_allowed — map to merge() into the workspace allow-list
#   token              — GitLab token value, for use in env blocks
#   vscode_settings    — VS Code settings map to merge() into the template's settings
# ─────────────────────────────────────────────────────────────────────────────

variable "repo_url" {
  type        = string
  description = "GitLab repository URL (without token), e.g. https://gitlab.com/org/repo.git."
}

variable "target_dir" {
  type        = string
  description = "Absolute path where the repository is cloned, e.g. /home/coder/my-repo."
}

variable "hooks_script" {
  type        = string
  default     = "setup-git-hooks.sh"
  description = "Script in the repo root to run after every successful clone/pull. Empty string disables."
}

variable "parameter_order" {
  type        = number
  default     = 1
  description = "Position of git parameters in the workspace form."
}

# ── VS Code extensions ────────────────────────────────────────────────────────
# Valid values:
#   gitlens   eamodio.gitlens

variable "extensions" {
  type        = list(string)
  default     = ["gitlens"]
  description = "Git-related VS Code extensions to include. Valid: gitlens."
}

# ── Data sources ──────────────────────────────────────────────────────────────

data "coder_workspace_owner" "me" {}

data "coder_parameter" "git_name" {
  name         = "git_name"
  display_name = "Git Name"
  description  = "Your name for git commits. Defaults to your Coder account name."
  type         = "string"
  mutable      = true
  default      = ""
  order        = var.parameter_order
}

data "coder_parameter" "gitlab_token" {
  name         = "gitlab_token"
  display_name = "GitLab Personal Access Token"
  description  = "Personal access token for GitLab (required for private repos). Leave empty for public repos."
  type         = "string"
  mutable      = true
  default      = ""
  order        = var.parameter_order + 1
  form_type    = "input"
  styling = jsonencode({
    mask_input = true
  })
}

# ── Locals ────────────────────────────────────────────────────────────────────

locals {
  _extension_ids = {
    "gitlens" = "eamodio.gitlens"
  }

  _selected_ext_ids = [
    for name in var.extensions : local._extension_ids[name]
    if contains(keys(local._extension_ids), name)
  ]

  _git_name  = data.coder_parameter.git_name.value != "" ? data.coder_parameter.git_name.value : data.coder_workspace_owner.me.name
  _git_email = data.coder_workspace_owner.me.email

  config = {
    repo_url     = var.repo_url
    token        = data.coder_parameter.gitlab_token.value
    target_dir   = var.target_dir
    git_name     = local._git_name
    git_email    = local._git_email
    hooks_script = var.hooks_script
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "startup_script" {
  description = "Bash snippet to interpolate into the template's coder_agent startup_script."
  value = templatefile("${path.module}/gitlab-dev.sh", {
    config_b64 = base64encode(jsonencode(local.config))
  })
}

output "extensions" {
  description = "VS Code extension IDs to pass to the code-server module's extensions list."
  value       = local._selected_ext_ids
}

output "extensions_allowed" {
  description = "Map to merge() into the workspace extensions.allowed policy."
  value       = { for id in local._selected_ext_ids : id => true }
}

output "token" {
  description = "GitLab token value, for use in env blocks."
  value       = data.coder_parameter.gitlab_token.value
  sensitive   = true
}

output "vscode_settings" {
  description = "VS Code settings map to merge() into the template's settings."
  value = {
    "gitlens.showWhatsNewAfterUpgrades"      = false
    "gitlens.plusFeatures.enabled"           = false
    "gitlens.launchpad.indicator.enabled"    = false
    "git.pruneOnFetch"                       = true
    "git.autofetch"                          = "all"
    "git.autofetchPeriod"                    = 180
    "git.openRepositoryInParentFolders"      = "always"
  }
}
