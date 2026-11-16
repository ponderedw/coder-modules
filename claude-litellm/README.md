# claude-litellm

Coder module: installs Claude Code (CLI + VS Code extension) and wires it to a LiteLLM proxy. Optionally installs generic AI CLI tools (`graphify`, `openspec`).

## What it does on every workspace start

1. Installs the pinned Claude Code CLI (skips if already at that version).
2. Installs / updates Claude Code plugins (e.g. dbt-agent-skills).
3. Merges MCP server entries into `~/.claude.json` without overwriting the rest of the file.
4. Installs AI tools listed in `var.ai_tools` (supported: `graphify`, `openspec`).
5. If a LiteLLM token is provided: writes `ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY`, and `ANTHROPIC_MODEL` into `~/.claude/settings.json` (user scope) and `~/.config/anthropic.env`.
6. Cleans stale ANTHROPIC_* keys from any `legacy_settings_files` so project-scope files can't shadow the user-scope settings.

## Outputs

| Output | Use |
|--------|-----|
| `startup_script` | Interpolate into `coder_agent.startup_script` |
| `vscode_extension` | Pass to `code-server` module's `extensions` list |
| `extensions_allowed` | `merge()` into your workspace allow-list |
| `litellm_token` | The raw token value, if another resource needs it |

## Minimal example

```hcl
module "claude" {
  source = "git::https://github.com/ponderedw/coder-modules.git//claude-litellm?ref=v1.0.0"

  litellm_base_url = "https://litellm.example.com"
  parameter_order  = 10
}

resource "coder_agent" "main" {
  startup_script = <<-EOT
    set -e
    # ... your setup ...
    ${module.claude.startup_script}
  EOT
}

module "code-server" {
  source  = "registry.coder.com/modules/code-server/coder"
  version = "1.4.4"

  agent_id   = coder_agent.main.id
  extensions = [module.claude.vscode_extension, "dracula-theme.theme-dracula"]
  settings   = {
    "extensions.allowed" = merge(
      module.claude.extensions_allowed,
      { "dracula-theme.theme-dracula" = true }
    )
  }
}
```

## With AI tools

```hcl
module "claude" {
  source = "git::https://github.com/ponderedw/coder-modules.git//claude-litellm?ref=v1.0.0"

  litellm_base_url = "https://litellm.example.com"
  parameter_order  = 10

  # CLI tools to install. Supported: "graphify", "openspec"
  ai_tools = ["graphify", "openspec"]
}
```

`graphify` is installed via `pipx` — ensure `pipx` is in your workspace image or apt install list.
`openspec` pulls nvm + Node 20 automatically.

## With MCP servers and plugins

```hcl
module "claude" {
  source = "git::https://github.com/ponderedw/coder-modules.git//claude-litellm?ref=v1.0.0"

  litellm_base_url = "https://litellm.example.com"
  parameter_order  = 10

  mcp_servers = {
    my-mcp = {
      type    = "stdio"
      command = "uvx"
      args    = ["my-mcp-package"]
      env     = { MY_VAR = "value" }
    }
  }

  plugins = [
    {
      marketplace_source = "my-org/my-plugin"
      marketplace_name   = "my-marketplace"
      plugin             = "my-plugin"
    }
  ]

  # Scrub ANTHROPIC_* keys from settings files written by older template versions
  # so they can't shadow the user-scope settings this module writes.
  legacy_settings_files = ["~/my-project/.claude/settings.local.json"]
}
```

## Composing allow-lists across modules

Each module outputs an `extensions_allowed` map. Merge them all in a local so Machine settings.json and the code-server module stay in sync:

```hcl
locals {
  extensions_allowed = merge(
    module.claude.extensions_allowed,   # { "anthropic.claude-code" = true }
    # module.dbt.extensions_allowed,    # add more modules here
    { "dracula-theme.theme-dracula" = true }
  )
}
```

## Variables reference

| Variable | Default | Description |
|----------|---------|-------------|
| `litellm_base_url` | `""` | LiteLLM proxy URL (`ANTHROPIC_BASE_URL`) |
| `model` | `claude-haiku-4-5-20251001` | Default Claude model |
| `subagent_model` | same | Model for sub-agents |
| `compaction_model` | same | Model for compaction |
| `claude_code_version` | `2.1.289` | Pinned CLI + extension version |
| `parameter_order` | `100` | Position of "LiteLLM Token" in the workspace form |
| `ai_tools` | `[]` | CLI tools to install (`graphify`, `openspec`) |
| `nvm_version` | `v0.40.5` | nvm version used for openspec |
| `mcp_servers` | `{}` | MCP server entries merged into `~/.claude.json` |
| `plugins` | `[]` | Claude Code plugins to install |
| `legacy_settings_files` | `[]` | Old settings files to scrub ANTHROPIC_* keys from |
| `install_cli` | `true` | Set `false` to skip CLI install (extension-only) |
