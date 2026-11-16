# claude-litellm

Shared Coder module: Claude Code (CLI + VS Code extension) wired to the LiteLLM proxy.
Defaults reproduce the dbt template's setup. It renders a bash snippet that you **add to**
your template's `startup_script`. It doesn't replace that script.

```hcl
module "claude" {
  source          = "git::https://github.com/ponderedw/coder-modules.git//claude-litellm?ref=v1.0.0"
  parameter_order = 6          # where "LiteLLM Token" appears in the workspace form
  # mcp_servers, plugins, legacy_settings_files, model, ... — see main.tf
}

resource "coder_agent" "main" {
  startup_script = <<-EOT
    set -e
    # ... your own setup ...
    ${module.claude.startup_script}
    # ... more of your own setup ...
  EOT
}

module "code-server" {
  extensions = [module.claude.vscode_extension, "..."]            # pinned to the CLI version
  settings   = { "extensions.allowed" = merge(module.claude.extensions_allowed, { ... }) }
}
```

The module defines the `litellm_token` workspace parameter itself. It keeps that name, so
existing workspaces keep their token.

Release flow: change the module → tag `vX.Y.Z` → bump `ref=` in each template → `coder templates push`.
