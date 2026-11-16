# gitlab-dev

Coder module: GitLab repository management and git tooling for Coder workspaces. Configures git identity, clones or pulls a repository on every start, optionally runs a hooks script, and outputs VS Code extensions (gitlens).

## What it does on every workspace start

1. Sets `git config --global` user.name and user.email (when provided).
2. If the target directory is an existing git repo: refreshes the remote URL (so a rotated token takes effect) then pulls.
3. If the target directory exists but is not a git repo: logs a warning and skips.
4. Otherwise: clones the repository using the provided token.
5. If `hooks_script` is set and the file exists in the repo root: runs it (useful for branch-protection hooks setup).

## Outputs

| Output | Use |
|--------|-----|
| `startup_script` | Interpolate into `coder_agent.startup_script` |
| `extensions` | Pass to `code-server` module's `extensions` list |
| `extensions_allowed` | `merge()` into your workspace allow-list |

## Minimal example

```hcl
module "gitlab" {
  source = "git::https://github.com/ponderedw/coder-modules.git//gitlab-dev?ref=v1.0.0"

  repo_url   = "https://gitlab.com/my-org/my-repo.git"
  token      = data.coder_parameter.gitlab_token.value
  target_dir = "/home/coder/my-repo"
  git_name   = data.coder_workspace_owner.me.name
  git_email  = data.coder_workspace_owner.me.email
}

resource "coder_agent" "main" {
  startup_script = <<-EOT
    set -e
    ${module.gitlab.startup_script}
  EOT
}
```

## With extensions

```hcl
module "gitlab" {
  source = "git::https://github.com/ponderedw/coder-modules.git//gitlab-dev?ref=v1.0.0"

  repo_url   = "https://gitlab.com/my-org/my-repo.git"
  token      = data.coder_parameter.gitlab_token.value
  target_dir = "/home/coder/my-repo"
  git_name   = data.coder_parameter.git_name.value != "" ? data.coder_parameter.git_name.value : data.coder_workspace_owner.me.name
  git_email  = data.coder_workspace_owner.me.email

  extensions = ["gitlens"]
}

locals {
  extensions_allowed = merge(
    module.gitlab.extensions_allowed,
    module.claude.extensions_allowed,
    module.dbt.extensions_allowed,
  )
}

module "code-server" {
  source  = "registry.coder.com/modules/code-server/coder"
  version = "1.4.4"

  agent_id   = coder_agent.main.id
  extensions = concat(
    module.gitlab.extensions,
    module.claude.extensions,
    module.dbt.extensions,
  )
  settings = {
    "extensions.allowed" = local.extensions_allowed
  }
}
```

## Variables reference

| Variable | Default | Description |
|----------|---------|-------------|
| `repo_url` | — | GitLab repository URL (required) |
| `token` | `""` | GitLab personal access token; leave empty for public repos |
| `target_dir` | — | Absolute local path to clone into (required) |
| `git_name` | `""` | `git config user.name`; skipped when empty |
| `git_email` | `""` | `git config user.email`; skipped when empty |
| `hooks_script` | `"setup-git-hooks.sh"` | Script in repo root to run after clone/pull; empty disables |
| `extensions` | `["gitlens"]` | VS Code extensions to include |

## Valid extension names

| Name | Extension ID |
|------|-------------|
| `gitlens` | `eamodio.gitlens` |
