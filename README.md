# gh-platform-actions

**Actions / policy layer** for gh-platform: reusable GitHub workflows that run secure OpenTofu delivery for caller (workload) repositories.

Primary deliverables:

- **`tofu-pipeline`** — multi-stage **validate → plan+OPA → gated apply**
- **`drift-reconcile`** — scheduled drift detect → Drift Report issue → optional non-destroy stamp PR

## Related repos

| Repo | What it does |
| --- | --- |
| [`gh-platform-modules`](https://github.com/ravichandrapatel/gh-platform-modules) | Versioned OpenTofu/AWS modules consumed by stacks |
| [`gh-platform-control`](https://github.com/ravichandrapatel/gh-platform-control) | IssueOps control plane (forms, codegen, pins, status) |
| Workload repos (`infra-dev` / `infra-prod`) | Call this pipeline on generated stacks |

## Layout

```text
.github/workflows/tofu-pipeline.yml     # reusable: validate → plan+OPA → gated apply
.github/workflows/drift-reconcile.yml   # reusable: drift report + optional stamp PR
scripts/drift_reconcile.py              # classifier / issue / stamp PR
policies/conftest/terraform/            # OPA/Conftest pack for module resources
policies/conftest/terraform-drift/      # deny destroy on drift/* PRs
docs/                                   # branching, rulesets, workflow docs
```

Policy details: [policies/conftest/terraform/README.md](policies/conftest/terraform/README.md).

## Reusable: tofu-pipeline

| Stage | Job | Contents |
| --- | --- | --- |
| 1 | `validate` | `tofu fmt -check`, `tofu validate` (after module download), Checkov |
| 2 | `plan` | `tofu plan` + Conftest/OPA |
| 3 | `apply` | Environment-gated `tofu apply` (plan artifact) |

Pass `secrets.modules_git_token` so private modules can be downloaded during `tofu init`.

See [docs/workflows/tofu-pipeline.md](docs/workflows/tofu-pipeline.md).

## Reusable: drift-reconcile

Workload-owned cron/dispatch. Classifies each `stacks/*` plan as clean / safe / destroy.
Destroy never gets a stamp PR. Dev may set `open_reconcile_pr: true`; prod should stay `false`.

See [docs/workflows/drift-reconcile.md](docs/workflows/drift-reconcile.md).

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

## Security branching

See [docs/BRANCHING.md](docs/BRANCHING.md). Apply [docs/GITHUB_RULESETS.md](docs/GITHUB_RULESETS.md) after the remote exists.

## Pinning

Callers must pin the reusable workflow to a 40-character commit SHA:

```yaml
uses: ravichandrapatel/gh-platform-actions/.github/workflows/tofu-pipeline.yml@<40-char-sha>
```
