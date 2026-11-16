terraform {
  required_version = ">= 1.3"
  required_providers {
    coder = {
      source = "coder/coder"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# dbt-dev — dbt toolchain for Coder workspaces.
#
# Outputs:
#   startup_script            — bash snippet for coder_agent startup_script
#   extensions                — list of VS Code extension IDs
#   extensions_allowed        — map to merge() into the workspace allow-list
#   sqltools_connections_json — JSON string for Machine settings "sqltools.connections"
#   dbt_cloud_token           — parsed dbt Cloud API token (sensitive)
#   vscode_settings           — VS Code settings map to merge()
#   yaml_disable_schema_detection — base glob list; concat project-specific paths
# ─────────────────────────────────────────────────────────────────────────────

# ── Tool installations ────────────────────────────────────────────────────────

variable "dbt_graphify_version" {
  type        = string
  default     = "0.1.5"
  description = "Version of dbt-graphify to install."
}

variable "dbt_graphify_watch_manifest" {
  type        = string
  default     = ""
  description = "Absolute path to dbt's manifest.json. Defaults to {project_dir}/target/manifest.json when project_dir is set."
}

variable "dbt_graphify_watch_out" {
  type        = string
  default     = ""
  description = "Output directory for the dbt-graphify watch process."
}

variable "dbt_fusion_version" {
  type        = string
  default     = ""
  description = "dbt Fusion (dbtf) version to pin. Empty string installs the latest available."
}

variable "install_dbt_fusion" {
  type        = bool
  default     = true
  description = "Install dbt Fusion (dbtf) binary."
}

variable "install_wizard" {
  type        = bool
  default     = true
  description = "Install dbt-wizard CLI."
}

variable "install_uv" {
  type        = bool
  default     = true
  description = "Install uv/uvx — required to run the dbt MCP server via `uvx dbt-mcp`."
}

variable "dbt_cloud_yml" {
  type        = string
  default     = ""
  description = "Full contents of dbt_cloud.yml to write to ~/.dbt/dbt_cloud.yml. Leave empty to skip."
  sensitive   = true
}

# ── Python dbt adapters ───────────────────────────────────────────────────────
# Each entry creates an isolated venv with dbt-core + dbt-{type}.
# Used for adapters not supported by dbt Fusion (e.g. Trino).
#
# Fields:
#   type            — adapter name: "trino", "bigquery", etc.
#   core_version    — dbt-core version to pin (empty = latest)
#   adapter_version — dbt-{type} version to pin (empty = latest)
#   venv_path       — venv location (empty = ~/.venvs/dbt-{type})

variable "adapters" {
  type = list(object({
    type            = string
    core_version    = optional(string, "")
    adapter_version = optional(string, "")
    venv_path       = optional(string, "")
    project_dir     = optional(string, "")  # when set, dbt dispatcher routes to this venv when PWD is inside this path
    command         = optional(string, "")  # CLI alias created in ~/.local/bin (default: dbt-{type}, e.g. "dbtt")
  }))
  default     = []
  description = "Python dbt adapters to install in isolated venvs. Each entry installs dbt-core + dbt-{type}."
}

# ── Project .env ──────────────────────────────────────────────────────────────

variable "project_dir" {
  type        = string
  default     = ""
  description = "Absolute path to the dbt project. Enables: .env writing, profiles.yml symlink, and auto-derive of dbt_graphify_watch_manifest."
}

variable "project_env_vars" {
  type        = map(string)
  default     = {}
  sensitive   = true
  description = "Env vars written as KEY='VALUE' lines to {project_dir}/.env. Used by dbt Fusion (loads .env from the project root)."
}

variable "gitignore_file" {
  type        = string
  default     = ""
  description = "Absolute path to a .gitignore to add .env to. Leave empty to skip."
}

# ── VS Code extensions ────────────────────────────────────────────────────────
# Valid values:
#   dbt              dbtLabsInc.dbt
#   jinja            samuelcolvin.jinjahtml
#   sqltools         mtxr.sqltools
#   sqltools-trino   akhilputhiry.sqltools-trino-driver
#   sqltools-pg      mtxr.sqltools-driver-pg
#   yaml             redhat.vscode-yaml
#   rainbow-csv      mechatroner.rainbow-csv
#   data-preview     RandomFractalsInc.vscode-data-preview
#   python           ms-python.python

variable "extensions" {
  type        = list(string)
  default     = ["dbt", "jinja", "sqltools", "yaml", "rainbow-csv", "data-preview"]
  description = "dbt-related VS Code extensions to include. See comment above for valid names."
}

# ── sqltools connections ──────────────────────────────────────────────────────
# Unified list replacing the separate trino / pg_connections variables.
#
# Fields common to all types:
#   type             — "trino", "pg", or "redshift" (pg and redshift use the PostgreSQL driver)
#   name             — display name in sqltools
#   host             — hostname
#   schema           — default schema
#   username         — login username
#   password         — login password
#   ssl              — TLS (default: true for trino, false for pg/redshift)
#   preview_limit    — row limit for table preview (default 50)
#
# Trino-specific:
#   catalog          — Trino catalog
#   extra_credential — forwarded as X-Trino-Extra-Credential headers
#
# pg/redshift-specific:
#   port             — TCP port (default 5439)
#   database         — database name

variable "connections" {
  type = list(object({
    type             = string
    name             = string
    host             = string
    port             = optional(number, null)
    catalog          = optional(string, "")
    database         = optional(string, "")
    schema           = optional(string, "")
    username         = optional(string, "")
    password         = optional(string, "")
    ssl              = optional(bool, null)
    preview_limit    = optional(number, 50)
    extra_credential = optional(map(string), {})
  }))
  default     = []
  description = "sqltools connections. type: trino, pg, or redshift."
}

# ── Locals ────────────────────────────────────────────────────────────────────

locals {
  _extension_ids = {
    "dbt"            = "dbtLabsInc.dbt"
    "jinja"          = "samuelcolvin.jinjahtml"
    "sqltools"       = "mtxr.sqltools"
    "sqltools-trino" = "akhilputhiry.sqltools-trino-driver"
    "sqltools-pg"    = "mtxr.sqltools-driver-pg"
    "yaml"           = "redhat.vscode-yaml"
    "rainbow-csv"    = "mechatroner.rainbow-csv"
    "data-preview"   = "RandomFractalsInc.vscode-data-preview"
    "python"         = "ms-python.python"
  }

  _selected_ext_ids = [
    for name in var.extensions : local._extension_ids[name]
    if contains(keys(local._extension_ids), name)
  ]

  # Derive manifest path from project_dir when not explicitly set.
  _watch_manifest = var.dbt_graphify_watch_manifest != "" ? var.dbt_graphify_watch_manifest : (
    var.project_dir != "" ? "${var.project_dir}/target/manifest.json" : ""
  )

  _trino_conns = [for c in var.connections : {
    name         = c.name
    driver       = "Trino Driver"
    server       = "https://${c.host}:443"
    catalog      = c.catalog
    schema       = c.schema
    user         = c.username
    password     = c.password
    previewLimit = c.preview_limit
    trinoOptions = merge(
      { ssl = { rejectUnauthorized = coalesce(c.ssl, true) } },
      length(c.extra_credential) > 0 ? { extraCredential = c.extra_credential } : {}
    )
  } if c.type == "trino"]

  _pg_conns = [for c in var.connections : {
    name         = c.name
    driver       = "PostgreSQL"
    server       = c.host
    port         = coalesce(c.port, 5439)
    database     = c.database
    username     = c.username
    password     = c.password
    pgOptions    = { ssl = { rejectUnauthorized = coalesce(c.ssl, false) } }
    previewLimit = c.preview_limit
  } if contains(["pg", "redshift"], c.type)]

  config = {
    install_dbt_fusion          = var.install_dbt_fusion
    dbt_fusion_version          = var.dbt_fusion_version
    adapters                    = var.adapters
    dbt_graphify_version        = var.dbt_graphify_version
    dbt_graphify_watch_manifest = local._watch_manifest
    dbt_graphify_watch_out      = var.dbt_graphify_watch_out
    install_wizard              = var.install_wizard
    install_uv                  = var.install_uv
    dbt_cloud_yml               = var.dbt_cloud_yml
    project_dir                 = var.project_dir
    project_env_vars            = var.project_env_vars
    gitignore_file              = var.gitignore_file
    install_snippets            = contains(var.extensions, "dbt")
    patch_sqltools_trino        = contains(var.extensions, "sqltools-trino")
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "dbt_cloud_token" {
  description = "dbt Cloud API token parsed from dbt_cloud_yml, for use in MCP server env."
  value       = try(regex("token-value:\\s*[\"']?([^\"'\\s]+)", var.dbt_cloud_yml)[0], "")
  sensitive   = true
}

output "startup_script" {
  description = "Bash snippet to interpolate into the template's coder_agent startup_script."
  value = templatefile("${path.module}/dbt-dev.sh", {
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

output "sqltools_connections_json" {
  description = "JSON string for Machine settings.json sqltools.connections."
  value       = jsonencode(concat(local._trino_conns, local._pg_conns))
}

output "vscode_settings" {
  description = "VS Code settings map to merge() into the template's settings."
  value = {
    "yaml.completion"         = true
    "yaml.schemaStore.enable" = true
    "yaml.format.printWidth"  = 100
    "yaml.schemas"            = { ".vscode/dbt_yml_files.json" = ".yml" }
  }
}

output "yaml_disable_schema_detection" {
  description = "Base list of glob patterns for yaml.disableSchemaDetection. Concat project-specific paths before passing to settings."
  value = [
    "**/dbt_project.yml",
    "**/dbt_project.yaml",
    "**/sources.yml",
    "**/sources.yaml",
    "**/groups.yml",
    "**/groups.yaml",
  ]
}
