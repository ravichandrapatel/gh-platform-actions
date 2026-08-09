# drift-reconcile (reusable workflow)

Detect OpenTofu drift across `stacks/**` on a workload repo. **Report** always. **Stamp PR** only for create/update-only stacks when enabled. **Never** auto-reconcile plans that include destroy.

## Behavior

| Class | Meaning | Action |
| --- | --- | --- |
| `clean` | No pending changes | Close Drift Report issue / stale stamp PR |
| `safe` | create / update only | Report + optional stamp PR (`open_reconcile_pr`) |
| `destroy` | any `delete` (incl. replace) | Report only — human triage |
| `error` | init/plan/API failure | Fail the job |

Stamp PR branch defaults to `drift/reconcile`. It only adds `stacks/<name>/.drift-reconcile` so existing `tofu.yml` path filters fire. `tofu-pipeline` runs an extra Conftest pack on `drift/*` PRs that **denies delete**.

## Trust

- Runs on the **workload** (OIDC plan role). Control never plans or applies.
- No GitHub Environment approval on detect (same idea as the pipeline `plan` job).
- IAM OIDC trust must allow the schedule/dispatch subject (usually `ref:refs/heads/main`).

## Caller example (dev — report + stamp PR)

```yaml
name: drift

on:
  schedule:
    - cron: "0 6 * * 1-5"
  workflow_dispatch:

permissions:
  contents: write
  pull-requests: write
  issues: write
  id-token: write

jobs:
  drift:
    uses: ravichandrapatel/gh-platform-actions/.github/workflows/drift-reconcile.yml@<40-char-sha>
    with:
      aws_role_arn: arn:aws:iam::ACCOUNT:role/gh-platform-dev
      aws_region: us-east-1
      open_reconcile_pr: true
      control_app_client_id: ${{ vars.CONTROL_CLIENT_ID }}
      modules_git_repository: ${{ vars.MODULES_GIT_REPOSITORY }}
    secrets:
      control_app_private_key: ${{ secrets.CONTROL_APP_PRIVATE_KEY }}
```

## Caller example (prod — report only)

```yaml
    with:
      aws_role_arn: arn:aws:iam::ACCOUNT:role/gh-platform-prod
      open_reconcile_pr: false
```

## How to solve drift

1. **Safe (dev):** review stamp PR → merge → Environment-gated apply restores Git desired state.
2. **Destroy:** read the Drift Report issue; either encode the cloud change into Git or open an explicit PR that intentionally deletes — never via quiet reconcile.
3. **Prod:** report-only; operator opens a normal workload PR.

## Related

- [`tofu-pipeline`](tofu-pipeline.md)
- Policy: `policies/conftest/terraform-drift/deny_destroy.rego`
- Script: `scripts/drift_reconcile.py`
