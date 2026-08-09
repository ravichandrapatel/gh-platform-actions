# guard-new-stacks

Composite action that refuses DIY `stacks/*` creates on workload repos.

## Behavior

- **Pass** when the PR only edits existing `stacks/<id>/` trees
- **Pass** when the PR adds exactly one new stack on branch `issueops/<stack_id>`, authored by a GitHub App (`*[bot]`), with valid `stack-metadata.json`
- **Fail** for human DIY (including owners/admins), spoofed `issueops/*` branches, or missing metadata

## Usage

Callers must check out the workload repo with `fetch-depth: 0` first. Keep the
job id `guard-new-stacks` so workload rulesets can require that check name.

```yaml
jobs:
  guard-new-stacks:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<sha> # pin
        with:
          fetch-depth: 0
      - uses: ravichandrapatel/gh-platform-actions/actions/security/guard-new-stacks@<40-char-sha>
        with:
          base_ref: origin/${{ github.base_ref }}
          head_ref_name: ${{ github.head_ref }}
          actor: ${{ github.actor }}
```

Pin the same commit SHA used for `tofu-pipeline` / `drift-reconcile`.
