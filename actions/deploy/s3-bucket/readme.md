# deploy/s3-bucket

Thin Actions-layer wrapper around `actions/iac/commons` for the `examples/s3-bucket` root module.

## Contract

Callers (control plane) must check out **this repository at the workspace root** (or ensure `./actions/iac/commons` resolves) before invoking this action, **or** call Commons directly with a pinned SHA:

```yaml
uses: OWNER/gh-platform-actions/actions/iac/commons@<sha>
```
