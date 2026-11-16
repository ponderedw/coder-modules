terraform {
  required_version = ">= 1.3"
  required_providers {
    coder = {
      source = "coder/coder"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# claude-litellm — Claude Code (CLI + VS Code extension) wired to the LiteLLM
# proxy. Shared by the dbt and Airflow Coder templates. The dbt template's
# setup is the reference: same pinned version, same models, same env.
#
# Usage: put "${module.claude.startup_script}" on its own line inside the
# template's startup_script, wherever it should run (it does NOT replace the
# template's script). On every workspace start the snippet:
#   1. Installs the Claude Code CLI at var.claude_code_version (skips when the
#      pinned version is already in ~/.local/bin; only records the version
#      after a successful install).
#   2. Installs/updates the Claude Code plugins in var.plugins.
#   3. Merges var.mcp_servers into ~/.claude.json "mcpServers" without wiping
#      the rest of that file (onboarding state, trusted folders, history).
#   4. Merges the LiteLLM env/model settings into ~/.claude/settings.json
#      (user scope — read by the CLI *and* the VS Code extension, whatever
#      folder is open). Other keys in that file are left alone.
#   5. Removes the managed ANTHROPIC_* keys from old settings files written
#      by earlier template versions (var.legacy_settings_files), so a stale
#      project-level file can't override the user-level settings.
#   6. Writes ~/.config/anthropic.env (sourced from ~/.bashrc) so any
#      Anthropic-SDK tool in the terminal (dbt wizard, etc.) uses LiteLLM.
# It runs in a subshell and never aborts the surrounding `set -e` script.
# ─────────────────────────────────────────────────────────────────────────────

variable "claude_code_version" {
  type        = string
  default     = "2.1.289"
  description = "Pinned version for both the CLI and the VS Code extension."
}

variable "litellm_base_url" {
  type    = string
  default = ""
}

variable "model" {
  type    = string
  default = "claude-haiku-4-5-20251001"
}

variable "subagent_model" {
  type    = string
  default = "claude-haiku-4-5-20251001"
}

variable "compaction_model" {
  type    = string
  default = "claude-haiku-4-5-20251001"
}

variable "parameter_order" {
  type        = number
  default     = 100
  description = "Position of the LiteLLM Token parameter in the workspace form."
}

variable "install_cli" {
  type    = bool
  default = true
}

variable "mcp_servers" {
  type        = any
  default     = {}
  description = "Map of MCP server name => Claude Code MCP config object. Merged into ~/.claude.json mcpServers."
}

variable "plugins" {
  type = list(object({
    marketplace_source = string # e.g. "dbt-labs/dbt-agent-skills"
    marketplace_name   = string # e.g. "dbt-agent-marketplace"
    plugin             = string # e.g. "dbt"
  }))
  default     = []
  description = "Claude Code plugins to install on first start and update on later starts."
}

variable "legacy_settings_files" {
  type        = list(string)
  default     = []
  description = "Settings files written by older template versions; the managed ANTHROPIC_* keys are removed from them."
}

variable "ai_tools" {
  type        = list(string)
  default     = []
  description = "AI-related CLI tools to install. Supported: graphify, dbt-graphify, openspec, wizard, uv."
}

variable "nvm_version" {
  type        = string
  default     = "v0.40.5"
  description = "nvm version for Node.js-based tools like openspec."
}


# Same parameter name as before ("litellm_token") so existing workspaces keep
# their value after the switch.
data "coder_parameter" "litellm_token" {
  name         = "litellm_token"
  display_name = "LiteLLM Token"
  description  = "API token for LiteLLM proxy (enables Claude Code via ${var.litellm_base_url})"
  type         = "string"
  mutable      = true
  default      = ""
  order        = var.parameter_order
  form_type    = "input"
  styling = jsonencode({
    mask_input = true
  })
}

locals {
  # Everything that could contain quotes or $ goes into the script base64-
  # encoded, so no shell or Coder-side expansion can mangle it.
  settings_env = {
    ANTHROPIC_BASE_URL         = var.litellm_base_url
    ANTHROPIC_API_KEY          = data.coder_parameter.litellm_token.value
    ANTHROPIC_AUTH_TOKEN       = data.coder_parameter.litellm_token.value
    ANTHROPIC_MODEL            = var.model
    CLAUDE_CODE_SUBAGENT_MODEL = var.subagent_model
  }
  config = {
    token                 = data.coder_parameter.litellm_token.value
    settings_env          = local.settings_env
    model_overrides       = { compaction = var.compaction_model }
    mcp_servers           = var.mcp_servers
    plugins               = var.plugins
    legacy_settings_files = var.legacy_settings_files
    ai_tools     = var.ai_tools
    nvm_version  = var.nvm_version
  }
}

output "startup_script" {
  description = "Bash snippet to interpolate into the template's coder_agent startup_script."
  value = templatefile("${path.module}/claude-litellm.sh", {
    claude_code_version = var.claude_code_version
    install_cli         = var.install_cli
    config_b64          = base64encode(jsonencode(local.config))
  })
  sensitive = true
}

output "vscode_extension" {
  description = "Pinned extension ID for the code-server module's `extensions` list."
  value       = "anthropic.claude-code@${var.claude_code_version}"
}

output "extensions_allowed" {
  description = "Entry to merge into the template's extensions.allowed map."
  value       = { "anthropic.claude-code" = true }
}

output "litellm_token" {
  description = "The token parameter value, in case the template needs it elsewhere."
  value       = data.coder_parameter.litellm_token.value
  sensitive   = true
}
