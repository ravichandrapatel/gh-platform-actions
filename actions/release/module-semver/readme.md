# module-semver

Derives the next **SemVer** for one module directory from conventional commits since the last module tag.

## Tag contract

| Item | Format | Example |
| --- | --- | --- |
| Tag | `{module}-v{MAJOR.MINOR.PATCH}` | `s3-v1.2.0` |
| Consume | `git::…//s3?ref=s3-v1.2.0` | pinned immutable ref |

## Bump rules

| Commit subject (after optional ticket prefix) | Bump |
| --- | --- |
| `feat:` / `feat(scope):` | minor |
| `fix:` / `chore:` / `perf:` | patch |
| `feat!:` / `fix!:` / `BREAKING CHANGE` | major |
| `docs:` `test:` `refactor:` `style:` `ci:` `build:` | none |
| First release (no prior tags) | `1.0.0` |

Only commits that **touch `{module}/`** since the last tag are considered.

## Inputs

| Input | Required | Description |
| --- | --- | --- |
| `module_name` | yes | Directory at repo root (e.g. `s3`) |
| `explicit_version` | no | Force `X.Y.Z` (skips commit scan) |

## Outputs

| Output | Description |
| --- | --- |
| `current_version` | Previous SemVer or `0.0.0` |
| `next_version` | Next SemVer |
| `tag_name` | Full tag (`s3-v1.2.0`) |
| `bump` | `major` \| `minor` \| `patch` \| `explicit` \| `initial` |

## Requirements

- Checkout with full history and tags (`fetch-depth: 0`).
- Workspace root must be the modules repository.
