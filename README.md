# gh-platform-actions

Reusable GitHub Actions and workflows for **gh-platform** (Actions layer + Commons).

## Related repos

| Repo | Role |
| --- | --- |
| `gh-platform-modules` | OpenTofu modules (pinned by tag) |
| `gh-platform-control` | Control plane that pins and dispatches these actions |

## Layout

```text
actions/iac/commons/              # OpenTofu runner (plan default)
actions/deploy/<name>/            # thin resource wrappers
.github/workflows/tofu-pipeline.yml   # reusable: Checkov → plan → Conftest → gated apply
policies/conftest/terraform/      # OPA/Conftest pack for all gh-platform-modules resources
docs/                             # branching, rulesets, workflow docs
```

Policy details: [policies/conftest/terraform/README.md](policies/conftest/terraform/README.md).

## Reusable: tofu-pipeline

Checkout → Checkov → `tofu init/plan` → Conftest (OPA) on plan JSON → gated `apply`.

See [docs/workflows/tofu-pipeline.md](docs/workflows/tofu-pipeline.md).

```yaml
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
      command: plan
```

## Security branching

See [docs/BRANCHING.md](docs/BRANCHING.md). Apply [docs/GITHUB_RULESETS.md](docs/GITHUB_RULESETS.md) after the remote exists.

## Pinning

Control plane and callers must pin:

```yaml
uses: OWNER/gh-platform-actions/actions/deploy/s3-bucket@<40-char-sha>
```
