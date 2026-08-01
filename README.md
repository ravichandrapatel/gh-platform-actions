# gh-platform-actions

Reusable GitHub Actions and workflows for **gh-platform** (Actions layer + Commons).

## Related repos

| Repo | Role |
| --- | --- |
| `gh-platform-modules` | OpenTofu modules (pinned by tag) |
| `gh-platform-control` | Control plane that pins and dispatches these actions |

## Layout

```text
actions/iac/commons/           # OpenTofu runner (plan default)
actions/deploy/<name>/         # thin resource wrappers
actions/release/module-semver/ # per-module SemVer calculation
.github/workflows/             # reusable + CI workflows
  module-release.yml           # validate + tag one module (SemVer)
docs/                          # branching + rulesets + workflow docs
```

## Module release (SemVer)

Reusable workflow for callers such as `gh-platform-modules`:

See [docs/workflows/module-release.md](docs/workflows/module-release.md).

Tag contract: `{module}-vX.Y.Z` (e.g. `s3-v1.0.0`).

## Security branching

See [docs/BRANCHING.md](docs/BRANCHING.md). Apply [docs/GITHUB_RULESETS.md](docs/GITHUB_RULESETS.md) after the remote exists.

## Pinning

Control plane and callers must pin:

```yaml
uses: OWNER/gh-platform-actions/actions/deploy/s3-bucket@<40-char-sha>
```
