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

Rego files live in [`policies/conftest/terraform/`](../../policies/conftest/terraform/).  
Override with input `policy_path` (still resolved inside this actions repo checkout).

Starter policies:

| File | Intent |
| --- | --- |
| `s3_encryption.rego` | S3 buckets need SSE configuration in-plan |
| `public_ingress.rego` | No SSH/RDP open to the world |
| `required_tags.rego` | `Environment` + `ManagedBy` on common resources |

## Related

- Legacy thin wrapper: [`.github/workflows/tofu-plan-apply.yml`](../../.github/workflows/tofu-plan-apply.yml)
- Commons composite: [`actions/iac/commons`](../../actions/iac/commons/)
