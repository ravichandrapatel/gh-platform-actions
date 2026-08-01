# tofu-pipeline (reusable workflow)

Secure OpenTofu delivery pipeline for caller repositories.

## Pipeline

1. Checkout caller repo
2. Checkout this actions repo (policy pack at `github.workflow_sha`)
3. AWS credentials via OIDC
4. **Checkov** (Terraform framework) on `working_directory`
5. `tofu init` + `tofu plan` → `tfplan.json`
6. **Conftest / OPA** against `policies/conftest/terraform`
7. `tofu apply` / `destroy` only when gated

## Apply / destroy gate

All of the following are required for mutating commands:

- `command: apply` (or `destroy`)
- `confirm_apply: APPLY`
- GitHub `environment` (attach required reviewers in repo settings)

Pull requests should call with `command: plan` only.

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
    uses: ravichandrapatel/gh-platform-actions/.github/workflows/tofu-pipeline.yml@<40-char-sha>
    with:
      working_directory: path/to/stack
      environment: nonprod
      aws_role_arn: arn:aws:iam::123456789012:role/gha-opentofu
      command: ${{ github.event_name == 'workflow_dispatch' && inputs.command || 'plan' }}
      confirm_apply: ${{ github.event_name == 'workflow_dispatch' && inputs.command == 'apply' && 'APPLY' || '' }}
```

## Custom policies

Rego pack: [`policies/conftest/terraform/`](../../policies/conftest/terraform/) — covers all `gh-platform-modules` resource types (S3, VPC/SG, IAM/SSO, compute, RDS, edge, Cognito, org, …).  
See [`policies/conftest/terraform/README.md`](../../policies/conftest/terraform/README.md) and [MODULE_COVERAGE.md](../../policies/conftest/terraform/MODULE_COVERAGE.md).

Override with input `policy_path` (still resolved inside this actions repo checkout).

## Related

- Legacy thin wrapper: [`.github/workflows/tofu-plan-apply.yml`](../../.github/workflows/tofu-plan-apply.yml)
- Commons composite: [`actions/iac/commons`](../../actions/iac/commons/)
