# module-release (reusable workflow)

Validate one OpenTofu/Terraform module and publish a **per-module SemVer tag**.

## Call from `gh-platform-modules`

```yaml
# .github/workflows/release-module.yml
name: release-module

on:
  workflow_dispatch:
    inputs:
      module_name:
        description: Module directory (e.g. s3)
        required: true
        type: string
      version:
        description: Optional explicit X.Y.Z
        required: false
        type: string
      dry_run:
        description: Validate + compute version only
        required: true
        type: boolean
        default: true

permissions:
  contents: write

jobs:
  release:
    uses: ravichandrapatel/gh-platform-actions/.github/workflows/module-release.yml@main
    with:
      module_name: ${{ inputs.module_name }}
      version: ${{ inputs.version }}
      dry_run: ${{ inputs.dry_run }}
```

Pin the `@main` ref to a commit SHA or release tag before production use.

## Tag format

`{module}-v{MAJOR.MINOR.PATCH}` — example: `s3-v1.2.0`

## SemVer rules

See [actions/release/module-semver/readme.md](../../actions/release/module-semver/readme.md).

## Defaults

- `dry_run: true` — no tag/release until you set `dry_run: false`
- OpenTofu `fmt` + `init -backend=false` + `validate` before tagging
