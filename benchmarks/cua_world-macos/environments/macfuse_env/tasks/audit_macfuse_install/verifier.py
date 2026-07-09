"""Verifier for audit_macfuse_install on macOS / macfuse_env.

Scoring (100 points, pass at 70):
    10 pts  C1   Report file exists, is fresh (mtime > task_start), and parses
                 as valid JSON. Partial: 5 (exists+valid but stale), 2 (exists+invalid).
     5 pts  C2   bundle_version matches the live CFBundleShortVersionString.
     5 pts  C3   bundle_identifier matches the live CFBundleIdentifier.
     5 pts  C4   pkg_core_version matches the live pkgutil version.
    20 pts  C5   core_pkg_install_time matches the live install-time within
                 ±install_time_tolerance_sec (sandbox-specific — unfakable).
    20 pts  C6   prefpane_pkg_install_time matches the live install-time within
                 ±install_time_tolerance_sec (sandbox-specific — unfakable).
     5 pts  C7   kext_currently_loaded == live kextstat state.
     5 pts  C8   mount_helper_path matches the live mount helper path.
    10 pts  C9   supported_macos_versions_count matches the live count.
     5 pts  C10  libfuse_dylib_count matches the live count.
    10 pts  C11  prefpane_installed matches the live state.

Partial-credit upper bound (no full credit on any criterion):
    Only C1 has a partial (5). Sum of partials = 5. Pass threshold 70 > 5
    by a wide margin (Anti-Pattern 4 safety).

Adversarial bound (agent guesses public facts without probing the live
install): the two install-time fields (40 pts together) are sandbox-specific
Unix epochs that the agent cannot know without running pkgutil. Max
guess-only score is 10 + 5 + 5 + 5 + 0 + 0 + 5 + 5 + 10 + 5 + 10 = 60,
strictly below the 70 pass threshold (Anti-Pattern 13 strategy enumeration).

Gates:
- Gate 1 (no work): no report at all → score 0.
- Gate 2 (strict wrong-target): report exists, parses as JSON, but contains
  zero mention of macfuse anywhere → score 0 regardless of file-existence
  partial credit (Pattern 2 in 03_verification_patterns.md).

Read pattern: copy_from_env(/tmp/audit_macfuse_install_result.json,
local_tmp) — produced by export_result.sh.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict


logger = logging.getLogger(__name__)

REMOTE_RESULT = "/tmp/audit_macfuse_install_result.json"
PASS_THRESHOLD = 70


def _empty_subscores() -> Dict[str, int]:
    return {
        "report_file": 0,
        "bundle_version": 0,
        "bundle_identifier": 0,
        "pkg_core_version": 0,
        "core_install_time": 0,
        "prefpane_install_time": 0,
        "kext_loaded": 0,
        "mount_helper_path": 0,
        "supported_versions_count": 0,
        "libfuse_count": 0,
        "prefpane_installed": 0,
    }


def _normalize_int(value: Any) -> int | None:
    """Coerce strings like '4' and integers to int; return None if not parseable."""
    if value is None:
        return None
    if isinstance(value, bool):
        # Reject bool — kext_loaded etc. must stay boolean; counts must be int.
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        try:
            return int(value.strip())
        except Exception:
            return None
    return None


def _normalize_bool(value: Any) -> bool | None:
    """Strict boolean coercion. Strings 'true'/'false' (case-insensitive) ok."""
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        lo = value.strip().lower()
        if lo == "true":
            return True
        if lo == "false":
            return False
    return None


def _within_tolerance(agent: Any, ground: int, tolerance: int) -> bool:
    agent_int = _normalize_int(agent)
    if agent_int is None or ground == 0:
        return False
    return abs(agent_int - ground) <= tolerance


def verify_audit_macfuse_install(
    traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]
) -> Dict[str, Any]:
    del traj
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"score": 0, "passed": False,
                "feedback": "env_info missing copy_from_env",
                "subscores": _empty_subscores()}

    metadata = (task_info or {}).get("metadata", {}) or {}
    tol = int(metadata.get("install_time_tolerance_sec", 2))
    pass_threshold = int(metadata.get("pass_threshold", PASS_THRESHOLD))

    # Pull the export JSON into a host-side temp file.
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        local_path = f.name
    try:
        try:
            copy_from_env(REMOTE_RESULT, local_path)
        except Exception as exc:
            logger.warning("copy_from_env failed: %s", exc)
            return {"score": 0, "passed": False,
                    "feedback": f"Could not retrieve result file from sandbox: {exc}",
                    "subscores": _empty_subscores()}
        try:
            with open(local_path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except Exception as exc:
            logger.warning("result JSON parse failed: %s", exc)
            return {"score": 0, "passed": False,
                    "feedback": f"Export produced unparseable JSON: {exc}",
                    "subscores": _empty_subscores()}
    finally:
        try:
            os.unlink(local_path)
        except Exception:
            pass

    report_exists = bool(data.get("report_exists", False))
    report_fresh = bool(data.get("report_fresh", False))
    report_valid_json = bool(data.get("report_valid_json", False))
    mentions_macfuse = bool(data.get("mentions_macfuse", False))

    # ---- Gate 1: no work at all ----
    if not report_exists:
        return {"score": 0, "passed": False,
                "feedback": "No evidence of task completion: no report file at "
                            "~/Documents/macfuse_audit_report.json.",
                "subscores": _empty_subscores()}

    # ---- Gate 2: strict wrong-target ----
    # Report exists, but mentions no macfuse content anywhere. Could be an
    # entirely different audit (wrong target). Pattern 2 in
    # 03_verification_patterns.md: immediate score=0.
    if report_exists and report_valid_json and not mentions_macfuse:
        return {"score": 0, "passed": False,
                "feedback": "Wrong target: report exists and parses as JSON but does not "
                            "mention macFUSE anywhere (no 'macfuse' or '/Library/Filesystems' "
                            "in the document body).",
                "subscores": _empty_subscores()}

    subscores = _empty_subscores()
    feedback: list[str] = []

    # ---- C1: report file (10 pts) ----
    if report_exists and report_valid_json and report_fresh:
        subscores["report_file"] = 10
        feedback.append("Report exists, fresh, valid JSON (+10)")
    elif report_exists and report_valid_json and not report_fresh:
        subscores["report_file"] = 5
        feedback.append("Report exists and valid JSON but mtime predates task start (+5)")
    elif report_exists and not report_valid_json:
        subscores["report_file"] = 2
        feedback.append("Report exists but does not parse as JSON (+2)")
    else:
        feedback.append("No report file at ~/Documents/macfuse_audit_report.json (+0)")

    # ---- Per-field exact-match checks ----
    fields = [
        ("bundle_version",            "agent_bundle_version",           "gt_bundle_version",            5,  "str"),
        ("bundle_identifier",         "agent_bundle_identifier",        "gt_bundle_identifier",         5,  "str"),
        ("pkg_core_version",          "agent_pkg_core_version",         "gt_pkg_core_version",          5,  "str"),
        ("kext_loaded",               "agent_kext_currently_loaded",    "gt_kext_currently_loaded",     5,  "bool"),
        ("mount_helper_path",         "agent_mount_helper_path",        "gt_mount_helper_path",         5,  "str"),
        ("supported_versions_count",  "agent_supported_macos_versions_count", "gt_supported_macos_versions_count", 10, "int"),
        ("libfuse_count",             "agent_libfuse_dylib_count",      "gt_libfuse_dylib_count",       5,  "int"),
        ("prefpane_installed",        "agent_prefpane_installed",       "gt_prefpane_installed",        10, "bool"),
    ]
    for sub_key, agent_key, gt_key, points, kind in fields:
        agent_val = data.get(agent_key)
        gt_val = data.get(gt_key)
        match = False
        if kind == "str":
            if isinstance(agent_val, str) and isinstance(gt_val, str) and gt_val:
                match = agent_val.strip() == gt_val.strip()
        elif kind == "int":
            a = _normalize_int(agent_val)
            g = _normalize_int(gt_val)
            match = a is not None and g is not None and a == g
        elif kind == "bool":
            a = _normalize_bool(agent_val)
            # gt may already be JSON bool; tolerate strings just in case.
            g = _normalize_bool(gt_val) if not isinstance(gt_val, bool) else gt_val
            match = a is not None and g is not None and a == g
        if match:
            subscores[sub_key] = points
            feedback.append(f"{sub_key}={agent_val!r} matches ground truth (+{points})")
        else:
            feedback.append(f"{sub_key}={agent_val!r} != GT {gt_val!r} (+0)")

    # ---- Install-time tolerance checks (sandbox-specific, unfakable) ----
    for sub_key, agent_key, gt_key, points in (
        ("core_install_time",     "agent_core_pkg_install_time",     "gt_core_pkg_install_time",     20),
        ("prefpane_install_time", "agent_prefpane_pkg_install_time", "gt_prefpane_pkg_install_time", 20),
    ):
        agent_val = data.get(agent_key)
        gt_val = int(data.get(gt_key) or 0)
        if _within_tolerance(agent_val, gt_val, tol):
            subscores[sub_key] = points
            feedback.append(f"{sub_key}={agent_val!r} within ±{tol}s of GT {gt_val} (+{points})")
        else:
            feedback.append(f"{sub_key}={agent_val!r} not within ±{tol}s of GT {gt_val} (+0)")

    total = sum(subscores.values())
    passed = total >= pass_threshold
    if passed:
        feedback.insert(0, f"PASSED ({total}/100, threshold {pass_threshold}): macFUSE audit complete with verified live values.")
    else:
        feedback.insert(0, f"FAILED ({total}/100, threshold {pass_threshold}): audit incomplete or inaccurate.")
    return {"score": total, "passed": passed, "feedback": " | ".join(feedback), "subscores": subscores}
