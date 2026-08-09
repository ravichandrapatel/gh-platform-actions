# gh-platform-actions

**Actions / policy layer** for gh-platform: reusable GitHub workflows that run secure OpenTofu delivery for caller (workload) repositories.

Primary deliverable: **`tofu-pipeline`** — multi-stage **validate → plan+OPA → gated apply**.

## Related repos

| Repo | What it does |
| --- | --- |
| [`gh-platform-modules`](https://github.com/ravichandrapatel/gh-platform-modules) | Versioned OpenTofu/AWS modules consumed by stacks |
| [`gh-platform-control`](https://github.com/ravichandrapatel/gh-platform-control) | IssueOps control plane (forms, codegen, pins, status) |
| Workload repos (`infra-dev` / `infra-prod`) | Call this pipeline on generated stacks |

## Layout

```text
.github/workflows/tofu-pipeline.yml   # reusable: validate → plan+OPA+C3X → gated apply
.github/workflows/drift-reconcile.yml # reusable: drift report (+ stamp PR when safe)
policies/conftest/terraform/          # OPA/Conftest pack for all gh-platform-modules resources
policies/checkov/                     # Checkov baseline for validate
actions/security/guard-new-stacks/    # composite: refuse DIY new stacks/*
actions/security/tfsec/               # composite: pinned tfsec
actions/cost/c3x-summary/             # composite: C3X cost → job summary (no API key)
docs/                                 # branching, rulesets, workflow docs
```

Policy details: [policies/conftest/terraform/README.md](policies/conftest/terraform/README.md).

## Reusable: tofu-pipeline

| Stage | Job | Contents |
| --- | --- | --- |
| 1 | `validate` | `tofu fmt -check`, `tofu validate` (after module download), Checkov, tfsec |
| 2 | `plan` | `tofu plan` + Conftest/OPA + C3X cost (job summary) |
| 3 | `apply` | Environment-gated `tofu apply` (plan artifact) |

Pass `secrets.modules_git_token` so private modules can be downloaded during `tofu init`.

See [docs/workflows/tofu-pipeline.md](docs/workflows/tofu-pipeline.md).

```yaml
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
      command: plan
    secrets:
      modules_git_token: ${{ secrets.MODULES_GIT_TOKEN }}
```

## Composite: guard-new-stacks

Workload `tofu.yml` keeps a job named **`guard-new-stacks`** (ruleset required check) and calls:

```yaml
- uses: ravichandrapatel/gh-platform-actions/actions/security/guard-new-stacks@<40-char-sha>
  with:
    base_ref: origin/${{ github.base_ref }}
    head_ref_name: ${{ github.head_ref }}
    actor: ${{ github.actor }}
```

See [actions/security/guard-new-stacks/readme.md](actions/security/guard-new-stacks/readme.md).

## Reusable: drift-reconcile

See [docs/workflows/drift-reconcile.md](docs/workflows/drift-reconcile.md). Callers pin the same SHA as `tofu-pipeline`.

## Security branching

See [docs/BRANCHING.md](docs/BRANCHING.md). Apply [docs/GITHUB_RULESETS.md](docs/GITHUB_RULESETS.md) after the remote exists.

## Pinning

Callers must pin the reusable workflow to a 40-character commit SHA:

```yaml
uses: ravichandrapatel/gh-platform-actions/.github/workflows/tofu-pipeline.yml@<40-char-sha>
```
