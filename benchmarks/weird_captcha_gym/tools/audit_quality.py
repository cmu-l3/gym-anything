#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

VISIBLE_HINT_PATTERNS = [
    "End the episode",
    "Awaiting final inspection",
    "This checkpoint is backwards",
    "Checksum rule",
    "one valid box",
    "decoys count",
    "submit after capture",
    "Target has entered",
    "Box evaded",
    "Box is tired",
    "Moving checkbox captured",
    "Checked-box result submitted",
    "scaffolded but does not have a renderer",
]

MIN_IMAGE_GRID_SCENES = 50


@dataclass
class Issue:
    severity: str
    category: str
    path: str
    detail: str


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def task_json_paths(task_id: str | None = None) -> list[Path]:
    paths = sorted((ROOT / "environments").glob("*_env/tasks/*/task.json"))
    if task_id is None:
        return paths
    return [path for path in paths if path.parent.name == task_id or load_json(path).get("id") == task_id]


def audit_task_metadata(issues: list[Issue], task_id: str | None = None) -> dict[str, int]:
    counts: dict[str, int] = {}
    paths = task_json_paths(task_id)
    if task_id and not paths:
        issues.append(Issue("blocker", "unknown_task", str(ROOT), f"task not found: {task_id}"))
        return counts
    for path in paths:
        data = load_json(path)
        metadata = data.get("metadata") or {}
        status = str(metadata.get("status") or "unknown")
        design_status = str(metadata.get("design_status") or "unknown")
        counts[status] = counts.get(status, 0) + 1

        if status == "scaffolded":
            issues.append(Issue("blocker", "scaffold_task", rel(path), "placeholder task, not benchmark-ready"))
        elif status.startswith("rejected_"):
            issues.append(Issue("blocker", "rejected_task", rel(path), f"{status} / {design_status}"))
        elif status.startswith("prototype_"):
            issues.append(Issue("blocker", "prototype_task", rel(path), f"{status} / {design_status}"))
        elif status != "benchmark_ready":
            issues.append(Issue("blocker", "unknown_status", rel(path), f"unexpected status {status!r}"))

        task_dir = path.parent
        verifier = task_dir / "verifier.py"
        if verifier.exists() and "scaffold verifier is not implemented" in verifier.read_text(encoding="utf-8"):
            issues.append(Issue("blocker", "placeholder_verifier", rel(verifier), "placeholder verifier"))
    return counts


def audit_visible_text(issues: list[Issue]) -> None:
    paths = [
        ROOT / "shared_runtime" / "app" / "app.js",
        ROOT / "shared_scripts" / "setup_task.py",
    ]
    for path in paths:
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        for pattern in VISIBLE_HINT_PATTERNS:
            if pattern in text:
                issues.append(Issue("blocker", "visible_hint_or_tutorial_copy", rel(path), pattern))


def audit_server_response_leaks(issues: list[Issue]) -> None:
    path = ROOT / "shared_runtime" / "server" / "weird_captcha_server.py"
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8")
    if re.search(r"response\s*\[[\"']feedback[\"']\]", text) or "feedback\": grade.get" in text:
        issues.append(Issue("blocker", "http_feedback_leak", rel(path), "submission response exposes diagnostic feedback"))


def audit_generator_variation(issues: list[Issue], task_id: str | None = None) -> None:
    if task_id and "surreal_apple_on_tree_grid" not in task_id:
        return
    path = ROOT / "shared_scripts" / "setup_task.py"
    if not path.exists():
        return
    spec = importlib.util.spec_from_file_location("weird_captcha_setup_task_audit", path)
    if spec is None or spec.loader is None:
        issues.append(Issue("blocker", "generator_import_failed", rel(path), "cannot import setup_task.py"))
        return
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    variant_count = int(getattr(module, "APPLE_GRID_VARIANT_COUNT", 0))
    if variant_count < MIN_IMAGE_GRID_SCENES:
        issues.append(
            Issue(
                "blocker",
                "low_variation_generator",
                rel(path),
                f"image-grid generator has {variant_count} relation variants; minimum is {MIN_IMAGE_GRID_SCENES}",
            )
        )


def print_report(counts: dict[str, int], issues: list[Issue]) -> None:
    print("Weird CAPTCHA Gym quality audit")
    print()
    print("Task status counts:")
    for status in sorted(counts):
        print(f"- {status}: {counts[status]}")
    print()
    if not issues:
        print("No issues found.")
        return
    print(f"Issues: {len(issues)}")
    for issue in issues:
        print(f"- [{issue.severity}] {issue.category}: {issue.path}: {issue.detail}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit Weird CAPTCHA Gym benchmark readiness.")
    parser.add_argument("--strict", action="store_true", help="exit non-zero when blockers are present")
    parser.add_argument("--task", help="audit one task id/folder instead of the full benchmark")
    args = parser.parse_args()

    issues: list[Issue] = []
    counts = audit_task_metadata(issues, args.task)
    audit_visible_text(issues)
    audit_server_response_leaks(issues)
    audit_generator_variation(issues, args.task)
    print_report(counts, issues)

    if args.strict and any(issue.severity == "blocker" for issue in issues):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
