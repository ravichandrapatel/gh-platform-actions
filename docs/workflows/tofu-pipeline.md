# tofu-pipeline (reusable workflow)

Secure multi-stage OpenTofu delivery pipeline for caller repositories.

## Stages

| Job | When | What |
| --- | --- | --- |
| `validate` | always | `tofu fmt -check` → `tofu init -backend=false` → `tofu validate` → **Checkov** (+ `policies/checkov/.checkov.yml`) → **tfsec** |
| `plan` | after validate | AWS OIDC → `tofu init` → `tofu plan` → **Conftest/OPA** on `tfplan.json` → **C3X** cost summary (job summary) → upload plan artifact |
| `apply` | `command=apply` + `confirm_apply=APPLY` | GitHub **Environment** gate → download plan → `tofu apply` |
| `destroy` | `command=destroy` + `confirm_apply=APPLY` | Environment gate → `tofu destroy` (no plan artifact) |

Environment protection (required reviewers) applies **only** to `apply` / `destroy`, so PR plans are not blocked by approvals.

OpenTofu CLI is used (`tofu`); it is Terraform-compatible (`fmt` / `validate` / `plan` / `apply`).

## Module download

Private git modules (e.g. `git::https://github.com/ORG/gh-platform-modules.git//s3?ref=…`) need a token that can `contents:read` those repos. Prefer minting a short-lived **GitHub App** installation token (same control App, scoped to the modules repo):

```yaml
with:
  control_app_client_id: ${{ vars.CONTROL_CLIENT_ID }}
  modules_git_repository: ${{ vars.MODULES_GIT_REPOSITORY }}  # owner/gh-platform-modules
secrets:
  control_app_private_key: ${{ secrets.CONTROL_APP_PRIVATE_KEY }}
  # optional PAT fallback:
  # modules_git_token: ${{ secrets.MODULES_GIT_TOKEN }}
```

The App must be installed on the **modules** repository (or All repos). EnvOps copies `CONTROL_CLIENT_ID` / `CONTROL_APP_PRIVATE_KEY` / `MODULES_GIT_REPOSITORY` onto new `infra-*` workloads.

`GITHUB_TOKEN` from the caller **cannot** read other private repositories by default.

The pipeline configures git `url.insteadOf` rewrites so HTTPS and SSH-style GitHub module sources authenticate with the minted (or fallback) token.

## Apply / destroy gate

All of the following are required for mutating commands:

- `command: apply` (or `destroy`)
- `confirm_apply: APPLY`
- GitHub `environment` on the apply/destroy job (attach required reviewers in repo settings)

Pull requests should call with `command: plan` only (runs `validate` + `plan`).

## Caller example

```yaml
name: deploy

on:
  pull_request:
  workflow_dispatch:
    inputs:
      command:
        type: choice
        options: [plan, apply]
        default: plan

permissions:
  contents: read
  id-token: write

jobs:
  tofu:
    permissions:
      contents: read
      id-token: write
      actions: write
    uses: ravichandrapatel/gh-platform-actions/.github/workflows/tofu-pipeline.yml@<40-char-sha>
    with:
      working_directory: path/to/stack
      environment: nonprod
      aws_role_arn: arn:aws:iam::123456789012:role/gha-opentofu
      control_app_client_id: ${{ vars.CONTROL_CLIENT_ID }}
      modules_git_repository: ${{ vars.MODULES_GIT_REPOSITORY }}
      command: ${{ github.event_name == 'workflow_dispatch' && inputs.command || 'plan' }}
      confirm_apply: ${{ github.event_name == 'workflow_dispatch' && inputs.command == 'apply' && 'APPLY' || '' }}
    secrets:
      control_app_private_key: ${{ secrets.CONTROL_APP_PRIVATE_KEY }}
```

## Custom policies

Rego pack: [`policies/conftest/terraform/`](../../policies/conftest/terraform/) — covers all `gh-platform-modules` resource types.  
See [`policies/conftest/terraform/README.md`](../../policies/conftest/terraform/README.md) and [MODULE_COVERAGE.md](../../policies/conftest/terraform/MODULE_COVERAGE.md).

Override with input `policy_path` (still resolved inside this actions repo checkout).

Checkov baseline: [`policies/checkov/.checkov.yml`](../../policies/checkov/.checkov.yml).

## Security scanners (validate)

| Tool | How | Soft-fail input |
| --- | --- | --- |
| Checkov | `bridgecrewio/checkov-action` + checkov.yml | `checkov_soft_fail` (default false) |
| tfsec | composite [`actions/security/tfsec`](../../actions/security/tfsec/) | `tfsec_soft_fail` (default false) |

## Cost estimate (plan summary)

[C3X](https://github.com/c3xdev/c3x) (Apache-2.0) estimates monthly cost from `tfplan.json` with **no API key**. Output is written to the GitHub Actions **job summary**.

Composite: [`actions/cost/c3x-summary`](../../actions/cost/c3x-summary/). Soft-fail by default (`c3x_soft_fail: true`) so pricing/network issues do not block the plan.
