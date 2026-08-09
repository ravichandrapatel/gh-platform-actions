# c3x-summary

Composite action that runs [C3X](https://github.com/c3xdev/c3x) against an OpenTofu/Terraform **plan JSON** and appends the monthly cost breakdown to the GitHub Actions job summary.

- No API key / account
- Binary + tarball SHA256 pinned in `action.yml`
- Soft-fail by default so pricing/network blips do not block apply-path PRs

## Usage

```yaml
- uses: ravichandrapatel/gh-platform-actions/actions/cost/c3x-summary@<40-char-sha>
  with:
    plan_path: ${{ inputs.working_directory }}/tfplan.json
    region: us-east-1
```

Used from `tofu-pipeline` after Conftest.
