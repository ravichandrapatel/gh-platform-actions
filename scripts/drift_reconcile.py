#!/usr/bin/env python3
"""
FILE_NAME: drift_reconcile.py
DESCRIPTION: Detect OpenTofu drift across stacks/**; classify destroy vs safe;
  upsert one Drift Report issue; optionally open a stamp PR for create/update-only.
VERSION: 0.1.0
EXIT_CODES: 0 = clean, 1 = error, 2 = drift (safe and/or destroy)
AUTHORS: gh-platform
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess  # nosec B404 — list-arg invocations only
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple
from urllib.parse import quote, urlparse

PREFIX = "[DRIFT-RECONCILE]"
DEFAULT_ISSUE_TITLE = "Infrastructure Drift Report"
STAMP_NAME = ".drift-reconcile"
DESTROY_ACTIONS = frozenset({"delete"})


def _log(msg: str) -> None:
    """INTENT: Prefixed stdout log. INPUT: msg. OUTPUT: None. SIDE_EFFECTS: stdout."""
    print(f"{PREFIX} {msg}", flush=True)


# ---------------------------------------------------------------------------
# GitHub API
# ---------------------------------------------------------------------------


class GitHubApiError(Exception):
    """ROLE: Data. INTENT: 4xx/5xx GitHub API failure."""

    def __init__(self, code: int, body: str) -> None:
        self.code = code
        self.body = body
        super().__init__(f"HTTP {code}: {body[:300]}")


class GitHubApiClient:
    """ROLE: Service. INTENT: Minimal GitHub REST client (stdlib)."""

    def __init__(self, token: str, api_url: Optional[str] = None) -> None:
        self._token = token.strip()
        self._base = (api_url or os.getenv("GITHUB_API_URL", "https://api.github.com")).rstrip("/")

    def _request(
        self,
        method: str,
        path: str,
        data: Optional[Dict[str, Any]] = None,
        *,
        ok_codes: Sequence[int] = (200, 201),
    ) -> Any:
        url = f"{self._base}{path}"
        if urlparse(url).scheme != "https":
            raise ValueError("Only https URLs are permitted for API calls")
        headers = {
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {self._token}",
            "User-Agent": "gh-platform-drift-reconcile",
            "X-GitHub-Api-Version": "2022-11-28",
        }
        body_bytes = None
        if data is not None:
            body_bytes = json.dumps(data).encode("utf-8")
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(url, data=body_bytes, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:  # nosec B310
                raw = resp.read().decode("utf-8")
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            if exc.code in ok_codes:
                return json.loads(body) if body else None
            raise GitHubApiError(exc.code, body) from exc


# ---------------------------------------------------------------------------
# Plan classification
# ---------------------------------------------------------------------------


@dataclass
class ResourceChange:
    """ROLE: Data. INTENT: One planned resource action summary."""

    address: str
    actions: List[str]


@dataclass
class StackResult:
    """ROLE: Data. INTENT: Drift classification for one stack root."""

    stack: str
    status: str  # clean | safe | destroy | error
    changes: List[ResourceChange] = field(default_factory=list)
    error: Optional[str] = None

    @property
    def has_destroy(self) -> bool:
        return self.status == "destroy"


def _extract_changes(plan: Dict[str, Any]) -> List[ResourceChange]:
    """INTENT: Pull non-no-op resource_changes from tofu show -json. INPUT: plan. OUTPUT: list."""
    out: List[ResourceChange] = []
    for rc in plan.get("resource_changes") or []:
        actions = list((rc.get("change") or {}).get("actions") or [])
        if not actions or actions == ["no-op"] or actions == ["read"]:
            continue
        # scrub: addresses only — never values
        out.append(ResourceChange(address=str(rc.get("address") or "?"), actions=actions))
    return out


def _classify(changes: List[ResourceChange]) -> str:
    """INTENT: safe (create/update only) vs destroy (any delete/replace). INPUT: changes. OUTPUT: status."""
    if not changes:
        return "clean"
    for c in changes:
        # replace = create+delete in one change — treat as destroy risk
        if any(a in DESTROY_ACTIONS for a in c.actions):
            return "destroy"
    return "safe"


def discover_stacks(stacks_root: Path) -> List[Path]:
    """INTENT: Find OpenTofu roots under stacks/* that contain .tf files. INPUT: root. OUTPUT: paths."""
    if not stacks_root.is_dir():
        return []
    found: List[Path] = []
    for child in sorted(stacks_root.iterdir()):
        if not child.is_dir() or child.name.startswith("."):
            continue
        if any(child.glob("*.tf")) or any(child.glob("*.tofu")):
            found.append(child)
    return found


def _run_stack_plan(
    stack_dir: Path,
    *,
    tofu_bin: str,
    tfvars_file: str,
    init_timeout: int,
    plan_timeout: int,
) -> StackResult:
    """INTENT: init + plan -out + show -json for one stack. INPUT: stack path. OUTPUT: StackResult."""
    stack = str(stack_dir.as_posix())
    env = os.environ.copy()
    env["TF_INPUT"] = "false"
    env["TF_IN_AUTOMATION"] = "1"

    def run(cmd: List[str], timeout: int) -> subprocess.CompletedProcess[str]:
        # list args only; tofu from PATH / pinned setup
        return subprocess.run(  # nosec B603
            cmd,
            cwd=str(stack_dir),
            env=env,
            capture_output=True,
            text=True,
            timeout=timeout,
        )

    try:
        # _log(f"[T-01] init {stack}")
        r = run([tofu_bin, "init", "-input=false", "-lock=false"], init_timeout)
        if r.returncode != 0:
            err = (r.stderr or r.stdout or "init failed")[:500]
            return StackResult(stack=stack, status="error", error=err)

        plan_cmd = [
            tofu_bin,
            "plan",
            "-input=false",
            "-lock=false",
            "-detailed-exitcode",
            "-out=tfplan.drift",
        ]
        if tfvars_file:
            plan_cmd.append(f"-var-file={tfvars_file}")
        r = run(plan_cmd, plan_timeout)
        if r.returncode == 0:
            return StackResult(stack=stack, status="clean")
        if r.returncode not in (1, 2):
            err = (r.stderr or r.stdout or f"plan exit {r.returncode}")[:500]
            return StackResult(stack=stack, status="error", error=err)
        if r.returncode == 1:
            err = (r.stderr or r.stdout or "plan failed")[:500]
            return StackResult(stack=stack, status="error", error=err)

        show = run([tofu_bin, "show", "-json", "tfplan.drift"], min(plan_timeout, 120))
        if show.returncode != 0:
            err = (show.stderr or show.stdout or "show -json failed")[:500]
            return StackResult(stack=stack, status="error", error=err)
        try:
            plan = json.loads(show.stdout or "{}")
        except json.JSONDecodeError as exc:
            return StackResult(stack=stack, status="error", error=f"plan JSON: {exc}")

        changes = _extract_changes(plan)
        status = _classify(changes)
        return StackResult(stack=stack, status=status, changes=changes)
    except subprocess.TimeoutExpired:
        return StackResult(stack=stack, status="error", error="timeout")
    except OSError as exc:
        return StackResult(stack=stack, status="error", error=str(exc)[:500])
    finally:
        plan_path = stack_dir / "tfplan.drift"
        if plan_path.exists():
            try:
                plan_path.unlink()
            except OSError:
                pass


def _change_excluded(stack: str, address: str, patterns: List[str]) -> bool:
    """INTENT: Match exclude pattern (substring or stack:substring)."""
    for pattern in patterns:
        if ":" in pattern:
            stack_part, addr_part = pattern.split(":", 1)
            if stack_part.strip() in stack and addr_part.strip() in address:
                return True
        elif pattern in address or pattern in stack:
            return True
    return False


def apply_excludes(results: List[StackResult], patterns: List[str]) -> List[StackResult]:
    """INTENT: Drop excluded changes; reclassify. INPUT: results, patterns. OUTPUT: filtered."""
    if not patterns:
        return results
    out: List[StackResult] = []
    for r in results:
        if r.status in ("clean", "error") or not r.changes:
            out.append(r)
            continue
        kept = [c for c in r.changes if not _change_excluded(r.stack, c.address, patterns)]
        if not kept:
            out.append(StackResult(stack=r.stack, status="clean"))
        else:
            out.append(StackResult(stack=r.stack, status=_classify(kept), changes=kept))
    return out


# ---------------------------------------------------------------------------
# Report + issue + PR
# ---------------------------------------------------------------------------


def build_markdown(
    results: List[StackResult],
    *,
    run_url: str,
    open_reconcile_pr: bool,
    pr_url: Optional[str],
) -> str:
    """INTENT: Single markdown Drift Report body. INPUT: results + meta. OUTPUT: md."""
    clean = [r for r in results if r.status == "clean"]
    safe = [r for r in results if r.status == "safe"]
    destroy = [r for r in results if r.status == "destroy"]
    errors = [r for r in results if r.status == "error"]
    lines = [
        "# Infrastructure Drift Report",
        "",
        f"**Generated:** {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%SZ')}",
        f"**Run:** {run_url or '(local)'}",
        f"**Reconcile PRs enabled:** `{open_reconcile_pr}`",
        "",
        "## Summary",
        "",
        "| Status | Count | Meaning |",
        "| --- | ---: | --- |",
        f"| clean | {len(clean)} | No pending changes |",
        f"| safe | {len(safe)} | create/update only — stamp PR eligible |",
        f"| destroy | {len(destroy)} | includes delete — **report only, no auto PR** |",
        f"| error | {len(errors)} | plan/init failed |",
        "",
    ]
    if pr_url:
        lines.extend([f"**Reconcile PR:** {pr_url}", ""])

    if destroy:
        lines.extend(
            [
                "## Destroy risk (no stamp PR)",
                "",
                "These stacks need human triage. Do **not** auto-apply.",
                "",
                "| Stack | Address | Actions |",
                "| --- | --- | --- |",
            ]
        )
        for r in destroy:
            for c in r.changes:
                if "delete" in c.actions:
                    lines.append(f"| `{r.stack}` | `{c.address}` | `{', '.join(c.actions)}` |")
        lines.append("")

    if safe:
        lines.extend(
            [
                "## Safe drift (create/update)",
                "",
                "| Stack | Address | Actions |",
                "| --- | --- | --- |",
            ]
        )
        for r in safe:
            for c in r.changes:
                lines.append(f"| `{r.stack}` | `{c.address}` | `{', '.join(c.actions)}` |")
        lines.append("")

    if errors:
        lines.extend(["## Errors", ""])
        for r in errors:
            lines.append(f"- `{r.stack}`: `{r.error}`")
        lines.append("")

    lines.extend(
        [
            "## How to solve",
            "",
            "1. **Safe drift (dev + reconcile enabled):** review/merge the stamp PR → "
            "`tofu-pipeline` plan → Environment-gated apply. Drift PRs deny destroy via Conftest.",
            "2. **Destroy risk:** inspect ClickOps vs desired Git state; fix with an explicit "
            "workload PR (or accept the cloud change into Git). Never merge a quiet reconcile for deletes.",
            "3. **Prod (report-only):** open a human PR or break-glass change; no auto stamp PR.",
            "",
        ]
    )
    return "\n".join(lines)


def upsert_issue(
    gh: GitHubApiClient,
    repo: str,
    title: str,
    body: str,
    *,
    has_drift: bool,
) -> Optional[int]:
    """INTENT: Create/update Drift Report issue; close when clean. OUTPUT: issue number."""
    owner, name = repo.split("/", 1)
    search = gh._request(
        "GET",
        f"/search/issues?q=repo:{owner}/{name}+type:issue+in:title+%22{quote(title)}%22",
    )
    items = (search or {}).get("items") or []
    issue_number: Optional[int] = None
    if items:
        # Prefer an open issue with this title; else the most recent.
        open_items = [i for i in items if i.get("state") == "open"]
        chosen = open_items[0] if open_items else items[0]
        issue_number = int(chosen["number"])
        state = "open" if has_drift else "closed"
        gh._request(
            "PATCH",
            f"/repos/{owner}/{name}/issues/{issue_number}",
            {"body": body, "state": state},
        )
        _log(f"Updated issue #{issue_number} → {state}")
        return issue_number

    if not has_drift:
        _log("Clean — no drift issue to create")
        return None

    created = gh._request(
        "POST",
        f"/repos/{owner}/{name}/issues",
        {"title": title, "body": body},
        ok_codes=(200, 201),
    )
    issue_number = int(created["number"])
    try:
        gh._request(
            "POST",
            f"/repos/{owner}/{name}/issues/{issue_number}/labels",
            {"labels": ["drift"]},
            ok_codes=(200, 201),
        )
    except GitHubApiError as exc:
        _log(f"label attach skipped: {exc}")
    _log(f"Opened issue #{issue_number}")
    return issue_number


def _ensure_label(gh: GitHubApiClient, repo: str, label: str) -> None:
    """INTENT: Best-effort create label. SIDE_EFFECTS: API."""
    owner, name = repo.split("/", 1)
    try:
        gh._request(
            "POST",
            f"/repos/{owner}/{name}/labels",
            {"name": label, "color": "B60205", "description": "Infrastructure drift"},
            ok_codes=(200, 201),
        )
    except GitHubApiError as exc:
        if exc.code not in (422,):  # already exists
            _log(f"label ensure skipped: {exc}")


def open_or_update_stamp_pr(
    gh: GitHubApiClient,
    repo: str,
    *,
    base: str,
    branch: str,
    safe_stacks: List[str],
    body: str,
    run_url: str,
) -> Optional[str]:
    """INTENT: Branch + stamp files + open/update PR for safe stacks only. OUTPUT: PR url."""
    if not safe_stacks:
        return None
    owner, name = repo.split("/", 1)
    ref = gh._request("GET", f"/repos/{owner}/{name}/git/ref/heads/{base}")
    base_sha = ref["object"]["sha"]

    # create or reset branch tip to base
    try:
        gh._request(
            "POST",
            f"/repos/{owner}/{name}/git/refs",
            {"ref": f"refs/heads/{branch}", "sha": base_sha},
            ok_codes=(200, 201),
        )
    except GitHubApiError as exc:
        if exc.code == 422:
            gh._request(
                "PATCH",
                f"/repos/{owner}/{name}/git/refs/heads/{branch}",
                {"sha": base_sha, "force": True},
            )
        else:
            raise

    stamp = (
        f"# drift-reconcile stamp — do not edit by hand\n"
        f"run: {run_url}\n"
        f"utc: {datetime.now(timezone.utc).isoformat()}\n"
    )
    for stack in safe_stacks:
        path = f"{stack.rstrip('/')}/{STAMP_NAME}"
        enc = quote(path, safe="/")
        try:
            existing = gh._request("GET", f"/repos/{owner}/{name}/contents/{enc}?ref={branch}")
            sha = existing.get("sha")
        except GitHubApiError as exc:
            if exc.code != 404:
                raise
            sha = None
        payload: Dict[str, Any] = {
            "message": f"chore(drift): stamp {stack}",
            "content": base64.b64encode(stamp.encode("utf-8")).decode("ascii"),
            "branch": branch,
        }
        if sha:
            payload["sha"] = sha
        gh._request("PUT", f"/repos/{owner}/{name}/contents/{enc}", payload)

    title = "chore(drift): reconcile create/update drift"
    prs = gh._request(
        "GET",
        f"/repos/{owner}/{name}/pulls?head={owner}:{branch}&state=open",
    )
    if prs:
        pr = prs[0]
        gh._request("PATCH", f"/repos/{owner}/{name}/pulls/{pr['number']}", {"body": body, "title": title})
        _log(f"Updated PR #{pr['number']}")
        return str(pr["html_url"])

    created = gh._request(
        "POST",
        f"/repos/{owner}/{name}/pulls",
        {"title": title, "head": branch, "base": base, "body": body},
        ok_codes=(200, 201),
    )
    _log(f"Opened PR #{created['number']}")
    return str(created["html_url"])


def close_stamp_pr_if_open(gh: GitHubApiClient, repo: str, branch: str) -> None:
    """INTENT: Close reconcile PR when drift is clean. SIDE_EFFECTS: API."""
    owner, name = repo.split("/", 1)
    prs = gh._request(
        "GET",
        f"/repos/{owner}/{name}/pulls?head={owner}:{branch}&state=open",
    )
    for pr in prs or []:
        gh._request(
            "PATCH",
            f"/repos/{owner}/{name}/pulls/{pr['number']}",
            {"state": "closed"},
        )
        _log(f"Closed stale reconcile PR #{pr['number']}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def _parse_exclude(raw: str) -> List[str]:
    if not raw or not raw.strip():
        return []
    text = raw.strip()
    if text.startswith("["):
        try:
            return [str(p).strip() for p in json.loads(text) if str(p).strip()]
        except json.JSONDecodeError:
            pass
    return [p.strip() for p in text.replace(",", "\n").splitlines() if p.strip()]


def main(argv: Optional[List[str]] = None) -> int:
    """INTENT: CLI entry. INPUT: argv. OUTPUT: exit code. SIDE_EFFECTS: plans, GitHub API."""
    p = argparse.ArgumentParser(description="gh-platform OpenTofu drift reconcile")
    p.add_argument("--stacks-root", default="stacks")
    p.add_argument("--tofu-bin", default="tofu")
    p.add_argument("--tfvars-file", default="")
    p.add_argument("--max-workers", type=int, default=4)
    p.add_argument("--init-timeout", type=int, default=300)
    p.add_argument("--plan-timeout", type=int, default=600)
    p.add_argument("--exclude", default="")
    p.add_argument("--repo", default=os.getenv("GITHUB_REPOSITORY", ""))
    p.add_argument("--token", default=os.getenv("GITHUB_TOKEN", ""))
    p.add_argument("--issue-title", default=DEFAULT_ISSUE_TITLE)
    p.add_argument("--open-reconcile-pr", action="store_true")
    p.add_argument("--reconcile-branch", default="drift/reconcile")
    p.add_argument("--base-branch", default="main")
    p.add_argument("--run-url", default=os.getenv("GITHUB_RUN_URL", ""))
    p.add_argument("--report-path", default="drift-report.md")
    p.add_argument("--skip-github", action="store_true")
    args = p.parse_args(argv)

    root = Path(args.stacks_root)
    stacks = discover_stacks(root)
    if not stacks:
        _log(f"No stacks under {root}; nothing to do")
        Path(args.report_path).write_text("# Infrastructure Drift Report\n\nNo stacks found.\n", encoding="utf-8")
        return 0

    _log(f"Planning {len(stacks)} stack(s) with {args.max_workers} workers")
    results: List[StackResult] = []
    with ThreadPoolExecutor(max_workers=max(1, args.max_workers)) as pool:
        futs = {
            pool.submit(
                _run_stack_plan,
                s,
                tofu_bin=args.tofu_bin,
                tfvars_file=args.tfvars_file,
                init_timeout=args.init_timeout,
                plan_timeout=args.plan_timeout,
            ): s
            for s in stacks
        }
        for fut in as_completed(futs):
            results.append(fut.result())
            r = results[-1]
            _log(f"{r.stack}: {r.status}" + (f" ({r.error})" if r.error else ""))

    results.sort(key=lambda r: r.stack)
    results = apply_excludes(results, _parse_exclude(args.exclude))

    safe = [r for r in results if r.status == "safe"]
    destroy = [r for r in results if r.status == "destroy"]
    errors = [r for r in results if r.status == "error"]
    has_drift = bool(safe or destroy)

    pr_url: Optional[str] = None
    gh: Optional[GitHubApiClient] = None
    if not args.skip_github and args.token and args.repo:
        gh = GitHubApiClient(args.token)
        _ensure_label(gh, args.repo, "drift")
        if args.open_reconcile_pr and safe and not errors:
            pr_body = (
                "## Drift reconcile (create/update only)\n\n"
                "This PR only stamps `.drift-reconcile` so `tofu-pipeline` re-plans/applies "
                "**Git desired state**. Stacks with **destroy** are excluded — see the Drift Report issue.\n\n"
                f"Run: {args.run_url}\n\n"
                "### Safe stacks\n"
                + "\n".join(f"- `{r.stack}`" for r in safe)
                + "\n"
            )
            if destroy:
                pr_body += (
                    "\n### Destroy stacks (not in this PR)\n"
                    + "\n".join(f"- `{r.stack}`" for r in destroy)
                    + "\n"
                )
            try:
                pr_url = open_or_update_stamp_pr(
                    gh,
                    args.repo,
                    base=args.base_branch,
                    branch=args.reconcile_branch,
                    safe_stacks=[r.stack for r in safe],
                    body=pr_body,
                    run_url=args.run_url,
                )
            except GitHubApiError as exc:
                _log(f"[ERR] stamp PR failed: {exc}")
                errors.append(
                    StackResult(stack="(reconcile-pr)", status="error", error=str(exc)[:500])
                )
        elif not has_drift:
            try:
                close_stamp_pr_if_open(gh, args.repo, args.reconcile_branch)
            except GitHubApiError as exc:
                _log(f"close PR skipped: {exc}")

    md = build_markdown(
        results,
        run_url=args.run_url,
        open_reconcile_pr=args.open_reconcile_pr,
        pr_url=pr_url,
    )
    Path(args.report_path).write_text(md, encoding="utf-8")
    _log(f"Wrote {args.report_path}")

    if gh and args.repo:
        try:
            upsert_issue(
                gh,
                args.repo,
                args.issue_title,
                md,
                has_drift=has_drift or bool(errors),
            )
        except GitHubApiError as exc:
            _log(f"[ERR] issue upsert failed: {exc}")
            return 1

    if errors:
        return 1
    if has_drift:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
