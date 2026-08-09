# tfsec

Pinned [tfsec](https://github.com/aquasecurity/tfsec) scan for Terraform/OpenTofu roots. Used in `tofu-pipeline` validate alongside Checkov.

```yaml
- uses: ravichandrapatel/gh-platform-actions/actions/security/tfsec@<40-char-sha>
  with:
    directory: stacks/my-stack
    soft_fail: "false"
```
