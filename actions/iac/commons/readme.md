# commons (IaC)

Runs OpenTofu against a **pinned** `gh-platform-modules` ref.

- Default `command=plan`
- `apply` / `destroy` require `confirm_apply=APPLY`
- Rejects floating refs: `main`, `master`, `HEAD`, `latest`
