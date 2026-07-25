"""Verifier for macfuse_python_passthrough on macOS / macfuse_env.

Scoring (100 points, pass at 70):
    15 pts  C1   mfusepy installed (`from fuse import FUSE, Operations` works).
    10 pts  C2   passthrough_fuse.py exists at /Users/lume/Documents/, fresh
                 (mtime > task_start), and >= min_script_bytes (default 500).
    10 pts  C3   Script contains a `from fuse import ...` or `import fuse`
                 line.
    10 pts  C4   At least one `class NAME(...Operations...)` declaration
                 appears in the script.
    20 pts  C5   At least required_method_min_count (default 5) of the FUSE
                 Operations methods are implemented: any of
                 {access, getattr, readdir, open, read, write, create,
                 release, flush}.
    10 pts  C6   Script references `fuse-access.log` (the file path the agent
                 should be logging to).
    10 pts  C7   Script contains a `FUSE(...)` call with `nothreads=True`
                 or `foreground=True` as a kwarg.
    10 pts  C8   Script passes `python3 -m py_compile` (export_result.sh runs
                 this and reports syntax_ok).
     5 pts  C9   Source directory ~/Documents/source/ exists with >= 1 file.

Pass threshold: 70.

Anti-Pattern 4 safety: every criterion is binary (no partial-credit
fractions). The largest no-real-work credit is C2 (10) + C9 (5) = 15,
well below the 70 pass threshold. C8 (10) requires a real Python file, but
an empty file passes py_compile too — combined with C2 + C9 that is still
25/100, far below 70. Reaching 70 requires actually implementing class +
methods + logging + FUSE call.

Gates:
- Gate 1 (no work): no script and no source dir → score 0.
- Gate 2 (wrong target): script exists but contains zero mention of "fuse"
  anywhere (case-insensitive). The agent wrote a Python file that is not
  a FUSE implementation. C2 + C8 + C9 still credited (file is real Python,
  source dir is real), but C3–C7 forced to zero.

Read pattern: copy_from_env(/tmp/macfuse_python_passthrough_result.json,
local_tmp) — produced by export_result.sh.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict


logger = logging.getLogger(__name__)

REMOTE_RESULT = "/tmp/macfuse_python_passthrough_result.json"
PASS_THRESHOLD = 70

POINTS = {
    "C1_mfusepy_installed":       15,
    "C2_script_exists":           10,
    "C3_fuse_import":             10,
    "C4_subclasses_operations":   10,
    "C5_method_count":            20,
    "C6_log_path":                10,
    "C7_fuse_call_flags":         10,
    "C8_syntax_ok":               10,
    "C9_source_dir":               5,
}


def _empty_subscores() -> Dict[str, int]:
    return {key: 0 for key in POINTS}


def verify_macfuse_python_passthrough(
    traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]
) -> Dict[str, Any]:
    del traj
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"score": 0, "passed": False,
                "feedback": "env_info missing copy_from_env",
                "subscores": _empty_subscores()}

    metadata = (task_info or {}).get("metadata", {}) or {}
    min_bytes = int(metadata.get("min_script_bytes", 500))
    min_methods = int(metadata.get("required_method_min_count", 5))
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

    mfusepy_importable = bool(data.get("mfusepy_importable", False))
    script_exists = bool(data.get("script_exists", False))
    script_fresh = bool(data.get("script_fresh", False))
    script_size = int(data.get("script_size", 0) or 0)
    syntax_ok = bool(data.get("syntax_ok", False))
    source_dir_exists = bool(data.get("source_dir_exists", False))
    source_file_count = int(data.get("source_file_count", 0) or 0)

    has_fuse_import = bool(data.get("has_fuse_import", False))
    subclasses_operations = bool(data.get("subclasses_operations", False))
    method_count = int(data.get("method_count", 0) or 0)
    method_names = data.get("method_names", []) or []
    logs_to_access_log = bool(data.get("logs_to_access_log", False))
    fuse_call_with_flags = bool(data.get("fuse_call_with_flags", False))
    mentions_fuse = bool(data.get("mentions_fuse", False))

    # ---- Gate 1: no work at all ----
    if not script_exists and not source_dir_exists:
        return {"score": 0, "passed": False,
                "feedback": "No evidence of task completion: neither "
                            "~/Documents/passthrough_fuse.py nor "
                            "~/Documents/source/ exists.",
                "subscores": _empty_subscores()}

    # ---- Gate 2: wrong target on the script ----
    # If the agent wrote a file that has zero connection to FUSE, treat
    # C3–C7 as a hard zero regardless of other content. C2 / C8 / C9
    # still apply because the file is real and the source dir is real.
    wrong_target = script_exists and not mentions_fuse

    subscores = _empty_subscores()
    feedback: list[str] = []

    # ---- C1: mfusepy installed (15) ----
    if mfusepy_importable:
        subscores["C1_mfusepy_installed"] = POINTS["C1_mfusepy_installed"]
        feedback.append("C1 PASS: `from fuse import FUSE, Operations` works (+15)")
    else:
        feedback.append("C1 FAIL: mfusepy not importable — run `pip install mfusepy` (+0)")

    # ---- C2: script exists, fresh, >= min_bytes (10) ----
    if script_exists and script_fresh and script_size >= min_bytes:
        subscores["C2_script_exists"] = POINTS["C2_script_exists"]
        feedback.append(
            f"C2 PASS: passthrough_fuse.py exists ({script_size} bytes >= {min_bytes}) (+10)"
        )
    else:
        if not script_exists:
            feedback.append("C2 FAIL: ~/Documents/passthrough_fuse.py not found (+0)")
        elif not script_fresh:
            feedback.append("C2 FAIL: passthrough_fuse.py is stale (mtime <= task_start) (+0)")
        else:
            feedback.append(
                f"C2 FAIL: passthrough_fuse.py is only {script_size} bytes (< {min_bytes}) (+0)"
            )

    # ---- C3: fuse import line (10) ----
    if has_fuse_import and not wrong_target:
        subscores["C3_fuse_import"] = POINTS["C3_fuse_import"]
        feedback.append("C3 PASS: `from fuse import ...` (or `import fuse`) present (+10)")
    else:
        if wrong_target:
            feedback.append("C3 FAIL: script contains no mention of fuse (wrong-target) (+0)")
        else:
            feedback.append("C3 FAIL: no `from fuse import ...` line found (+0)")

    # ---- C4: subclasses Operations (10) ----
    if subclasses_operations and not wrong_target:
        subscores["C4_subclasses_operations"] = POINTS["C4_subclasses_operations"]
        feedback.append("C4 PASS: a class subclassing `Operations` is declared (+10)")
    else:
        feedback.append("C4 FAIL: no `class X(...Operations...)` declaration found (+0)")

    # ---- C5: >= min_methods of the FUSE op methods implemented (20) ----
    if method_count >= min_methods and not wrong_target:
        subscores["C5_method_count"] = POINTS["C5_method_count"]
        feedback.append(
            f"C5 PASS: {method_count} FUSE methods implemented "
            f"({', '.join(method_names)}) >= {min_methods} (+20)"
        )
    else:
        feedback.append(
            f"C5 FAIL: only {method_count} FUSE methods found "
            f"({', '.join(method_names) if method_names else 'none'}); need >= {min_methods} (+0)"
        )

    # ---- C6: logging to fuse-access.log (10) ----
    if logs_to_access_log and not wrong_target:
        subscores["C6_log_path"] = POINTS["C6_log_path"]
        feedback.append("C6 PASS: script references `fuse-access.log` (+10)")
    else:
        feedback.append("C6 FAIL: script does not reference `fuse-access.log` (+0)")

    # ---- C7: FUSE() call with nothreads or foreground True (10) ----
    if fuse_call_with_flags and not wrong_target:
        subscores["C7_fuse_call_flags"] = POINTS["C7_fuse_call_flags"]
        feedback.append("C7 PASS: `FUSE(...)` called with nothreads=True or foreground=True (+10)")
    else:
        feedback.append("C7 FAIL: no `FUSE(...)` call with nothreads=True or foreground=True (+0)")

    # ---- C8: python3 -m py_compile passes (10) ----
    if syntax_ok and script_exists:
        subscores["C8_syntax_ok"] = POINTS["C8_syntax_ok"]
        feedback.append("C8 PASS: `python3 -m py_compile` succeeds (+10)")
    else:
        feedback.append("C8 FAIL: `python3 -m py_compile` failed or script missing (+0)")

    # ---- C9: source dir exists with at least 1 file (5) ----
    if source_dir_exists and source_file_count >= 1:
        subscores["C9_source_dir"] = POINTS["C9_source_dir"]
        feedback.append(
            f"C9 PASS: ~/Documents/source/ exists with {source_file_count} file(s) (+5)"
        )
    else:
        if not source_dir_exists:
            feedback.append("C9 FAIL: ~/Documents/source/ does not exist (+0)")
        else:
            feedback.append("C9 FAIL: ~/Documents/source/ exists but is empty (+0)")

    total = sum(subscores.values())
    passed = total >= pass_threshold
    if passed:
        feedback.insert(
            0,
            f"PASSED ({total}/100, threshold {pass_threshold}): "
            f"FUSE passthrough implementation complete.",
        )
    else:
        feedback.insert(
            0,
            f"FAILED ({total}/100, threshold {pass_threshold}): "
            f"passthrough implementation incomplete.",
        )
    return {
        "score": total,
        "passed": passed,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
    }
