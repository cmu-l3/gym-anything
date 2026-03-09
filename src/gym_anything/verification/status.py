from __future__ import annotations

import json
import re
from collections import Counter, defaultdict
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict

from .reports import VerificationRecord, VerificationSummary


def _task_components(root: Path, record: VerificationRecord) -> Dict[str, Any]:
    record_path = Path(record.path)
    try:
        relative = record_path.relative_to(root)
    except ValueError:
        relative = record_path

    env_name = relative.parts[0] if len(relative.parts) >= 1 else ""
    task_id = relative.parts[2] if len(relative.parts) >= 3 and relative.parts[1] == "tasks" else record_path.parent.name
    task_ref = f"{env_name}/{task_id}" if env_name else task_id

    return {
        "environment": env_name,
        "task_id": task_id,
        "task_ref": task_ref,
        "task_spec_path": str(relative),
    }


def build_task_status_manifest(summary: VerificationSummary) -> Dict[str, Any]:
    root = Path(summary.root)
    issue_counts: Counter[str] = Counter()
    verified_tasks = []
    failed_tasks = []
    by_environment: Dict[str, Dict[str, Any]] = defaultdict(
        lambda: {"verified_tasks": [], "failed_tasks": [], "issue_counts": Counter()}
    )

    task_records = [record for record in summary.records if record.kind == "task"]
    for record in task_records:
        task_info = _task_components(root, record)
        entry = {
            **task_info,
            "spec_id": record.spec_id,
            "status": "verified" if record.ok else "failed",
        }
        if record.issues:
            entry["issues"] = [asdict(issue) for issue in record.issues]
            for issue in record.issues:
                issue_counts[issue.code] += 1
                by_environment[task_info["environment"]]["issue_counts"][issue.code] += 1

        if record.ok:
            verified_tasks.append(entry)
            by_environment[task_info["environment"]]["verified_tasks"].append(task_info["task_id"])
        else:
            failed_tasks.append(entry)
            by_environment[task_info["environment"]]["failed_tasks"].append(task_info["task_id"])

    normalized_by_environment: Dict[str, Dict[str, Any]] = {}
    for env_name, env_data in by_environment.items():
        normalized_by_environment[env_name] = {
            "verified_tasks": sorted(env_data["verified_tasks"]),
            "failed_tasks": sorted(env_data["failed_tasks"]),
            "issue_counts": dict(sorted(env_data["issue_counts"].items())),
        }

    return {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "root": summary.root,
        "total_task_records": len(task_records),
        "verified_task_count": len(verified_tasks),
        "failed_task_count": len(failed_tasks),
        "issue_counts": dict(sorted(issue_counts.items())),
        "verified_tasks": verified_tasks,
        "failed_tasks": failed_tasks,
        "by_environment": dict(sorted(normalized_by_environment.items())),
    }


def build_verified_task_split(summary: VerificationSummary) -> Dict[str, Any]:
    root = Path(summary.root)
    by_environment: Dict[str, list[str]] = defaultdict(list)
    task_refs = []

    for record in summary.records:
        if record.kind != "task" or not record.ok:
            continue
        task_info = _task_components(root, record)
        by_environment[task_info["environment"]].append(task_info["task_id"])
        task_refs.append(task_info["task_ref"])

    return {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "root": summary.root,
        "task_count": len(task_refs),
        "tasks": sorted(task_refs),
        "by_environment": {env: sorted(task_ids) for env, task_ids in sorted(by_environment.items())},
    }


_MISSING_HOOK_RE = re.compile(r"^(?P<hook>[a-zA-Z0-9_]+) references missing script\(s\): (?P<assets>.+)$")


def _extract_missing_hook_assets(record: VerificationRecord) -> list[Dict[str, str]]:
    missing_assets: list[Dict[str, str]] = []
    for issue in record.issues:
        if issue.code != "missing_hook_reference":
            continue
        match = _MISSING_HOOK_RE.match(issue.message)
        if not match:
            missing_assets.append({"hook": "unknown", "asset": issue.message})
            continue
        hook_name = match.group("hook")
        assets = [asset.strip() for asset in match.group("assets").split(",") if asset.strip()]
        for asset in assets:
            missing_assets.append({"hook": hook_name, "asset": asset})
    return missing_assets


def build_missing_hook_reference_manifest(summary: VerificationSummary) -> Dict[str, Any]:
    root = Path(summary.root)
    tasks = []
    by_environment: Dict[str, Dict[str, Any]] = defaultdict(
        lambda: {"task_dirs": [], "task_ids": [], "missing_assets": []}
    )

    for record in summary.records:
        if record.kind != "task":
            continue
        missing_assets = _extract_missing_hook_assets(record)
        if not missing_assets:
            continue

        task_info = _task_components(root, record)
        task_dir = str(Path(summary.root) / Path(task_info["task_spec_path"]).parent)
        entry = {
            **task_info,
            "task_dir": task_dir,
            "spec_id": record.spec_id,
            "missing_hook_assets": missing_assets,
            "issues": [asdict(issue) for issue in record.issues if issue.code == "missing_hook_reference"],
        }
        tasks.append(entry)

        env_bucket = by_environment[task_info["environment"]]
        env_bucket["task_dirs"].append(task_dir)
        env_bucket["task_ids"].append(task_info["task_id"])
        env_bucket["missing_assets"].extend(missing_assets)

    normalized_by_environment: Dict[str, Dict[str, Any]] = {}
    for env_name, env_data in by_environment.items():
        normalized_by_environment[env_name] = {
            "task_count": len(env_data["task_ids"]),
            "task_ids": sorted(env_data["task_ids"]),
            "task_dirs": sorted(env_data["task_dirs"]),
            "missing_hook_asset_count": len(env_data["missing_assets"]),
        }

    return {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "root": summary.root,
        "task_count": len(tasks),
        "environment_count": len(normalized_by_environment),
        "tasks": tasks,
        "by_environment": dict(sorted(normalized_by_environment.items())),
    }


def write_json_report(data: Dict[str, Any], out_path: Path) -> None:
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


__all__ = [
    "build_missing_hook_reference_manifest",
    "build_task_status_manifest",
    "build_verified_task_split",
    "write_json_report",
]
