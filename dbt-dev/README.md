# dbt-dev

Coder module: dbt toolchain for Coder workspaces. Installs dbt-graphify (with optional watch mode), dbt-wizard, and uv/uvx. Outputs VS Code extensions and sqltools connection config so templates can compose them with other modules.

## What it does on every workspace start

1. Installs / updates `dbt-graphify` at the pinned version.
2. If `dbt_graphify_watch_manifest` is set: (re)starts `dbt-graphify --watch` as a background process, replacing any stale PID from a previous start.
3. If `install_wizard = true`: installs `dbt-wizard` (skips if already present).
4. If `install_uv = true`: installs `uv` / `uvx` via pipx (required to run the dbt MCP server via `uvx dbt-mcp`).

## Outputs

| Output | Use |
|--------|-----|
| `startup_script` | Interpolate into `coder_agent.startup_script` |
| `extensions` | Pass to `code-server` module's `extensions` list |
| `extensions_allowed` | `merge()` into your workspace allow-list |
| `sqltools_connections_json` | Embed in Machine `settings.json` as `sqltools.connections` |

## Minimal example

```hcl
module "dbt" {
  source = "git::https://github.com/ponderedw/coder-modules.git//dbt-dev?ref=v1.0.0"
}

resource "coder_agent" "main" {
  startup_script = <<-EOT
    set -e
    ${module.dbt.startup_script}
  EOT
}
```

## With dbt-graphify watch and extensions

```hcl
module "dbt" {
  source = "git::https://github.com/ponderedw/coder-modules.git//dbt-dev?ref=v1.0.0"

  # dbt-graphify watch — restarts automatically on each workspace start
  dbt_graphify_watch_manifest = "/home/coder/my-dbt-project/target/manifest.json"
  dbt_graphify_watch_out      = "/home/coder/my-dbt-project/graphify-out"

  # Pick extensions from the predefined list (see Valid values below)
  extensions = ["dbt", "jinja", "sqltools", "sqltools-trino", "sqltools-pg", "yaml", "rainbow-csv", "data-preview", "gitlens", "python"]
}
```

## With sqltools connections

```hcl
module "dbt" {
  source = "git::https://github.com/ponderedw/coder-modules.git//dbt-dev?ref=v1.0.0"

  extensions = ["dbt", "jinja", "sqltools", "sqltools-trino", "sqltools-pg", "yaml"]

  trino = {
    host     = data.coder_parameter.trino_host.value
    catalog  = data.coder_parameter.trino_catalog.value
    schema   = data.coder_parameter.trino_schema.value
    user     = data.coder_parameter.trino_user.value
    password = data.coder_parameter.trino_password.value
    # Optional: forward Redshift credentials through Trino's X-Trino-Extra-Credential header
    extra_credential = {
      "redshift.user"     = data.coder_parameter.db_user.value
      "redshift.password" = data.coder_parameter.db_password.value
    }
  }

  pg_connections = [
    {
      name     = "My Redshift"
      host     = data.coder_parameter.db_host.value
      database = data.coder_parameter.db_name.value
      username = data.coder_parameter.db_user.value
      password = data.coder_parameter.db_password.value
    }
  ]
}
```

Then wire the outputs into your agent and code-server:

```hcl
resource "coder_agent" "main" {
  startup_script = <<-EOT
    set -e
    ${module.dbt.startup_script}
  EOT
}

locals {
  extensions_allowed = merge(
    module.claude.extensions_allowed,  # from claude-litellm
    module.dbt.extensions_allowed,
    { "dracula-theme.theme-dracula" = true }
  )
}

module "code-server" {
  source  = "registry.coder.com/modules/code-server/coder"
  version = "1.4.4"

  agent_id   = coder_agent.main.id
  extensions = concat(
    [module.claude.vscode_extension, "dracula-theme.theme-dracula"],
    module.dbt.extensions
  )
  settings = {
    "extensions.allowed"   = local.extensions_allowed
    "sqltools.connections" = jsondecode(module.dbt.sqltools_connections_json)
  }
}
```

Machine `settings.json` (written early in startup_script so the allow-list is ready before extension install):

```bash
cat > ~/.local/share/code-server/Machine/settings.json << 'EOF'
{
  "extensions.allowed": ${jsonencode(local.extensions_allowed)},
  "sqltools.connections": ${module.dbt.sqltools_connections_json}
}
EOF
```

## Composing allow-lists across modules

`extensions_allowed` is a plain `map(bool)` — Terraform's `merge()` acts as an upsert, so any number of modules can contribute without conflicts:

```hcl
extensions_allowed = merge(
  module.claude.extensions_allowed,
  module.dbt.extensions_allowed,
  { "my-org.my-extension" = true }
)
```

## Valid extension names

| Name | Extension ID |
|------|-------------|
| `dbt` | `dbtLabsInc.dbt` |
| `jinja` | `samuelcolvin.jinjahtml` |
| `sqltools` | `mtxr.sqltools` |
| `sqltools-trino` | `akhilputhiry.sqltools-trino-driver` |
| `sqltools-pg` | `mtxr.sqltools-driver-pg` |
| `yaml` | `redhat.vscode-yaml` |
| `rainbow-csv` | `mechatroner.rainbow-csv` |
| `data-preview` | `RandomFractalsInc.vscode-data-preview` |
| `python` | `ms-python.python` |

> **Note:** `gitlens` has moved to the `gitlab-dev` module.

## Variables reference

| Variable | Default | Description |
|----------|---------|-------------|
| `install_dbt_fusion` | `true` | Install dbt Fusion (`dbtf`) binary |
| `dbt_fusion_version` | `""` | Pin a specific dbt Fusion version; empty installs latest |
| `install_dbt_trino` | `false` | Create an isolated dbt-core + dbt-trino venv |
| `dbt_trino_venv_path` | `"/home/coder/.venvs/dbt-trino"` | Path for the dbt-trino venv |
| `dbt_graphify_version` | `0.1.5` | Version of dbt-graphify to install |
| `dbt_graphify_watch_manifest` | `""` | Path to `manifest.json`; enables watch mode when set |
| `dbt_graphify_watch_out` | `""` | Output directory for the watch process |
| `install_wizard` | `true` | Install dbt-wizard CLI |
| `install_uv` | `true` | Install uv/uvx (needed for `uvx dbt-mcp`) |
| `dbt_cloud_yml` | `""` | Contents of `dbt_cloud.yml`; written to `~/.dbt/dbt_cloud.yml` when set |
| `extensions` | `["dbt","jinja","sqltools","yaml","rainbow-csv","data-preview"]` | Extensions to include |
| `trino` | `null` | Trino sqltools connection (omitted when null) |
| `pg_connections` | `[]` | PostgreSQL/Redshift sqltools connections |

## Automatic behaviours driven by `extensions`

- **Snippets**: when `"dbt"` is in `extensions`, writes `~/.local/share/code-server/User/snippets/dbt.code-snippets` on every start (overwritten so template updates propagate).
- **sqltools-trino patch**: when `"sqltools-trino"` is in `extensions`, starts a background process that waits for the extension to be installed then patches `plugin.js` to forward `trinoOptions.extraCredential` as the `X-Trino-Extra-Credential` header.
