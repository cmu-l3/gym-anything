"""Verifier for macfuse_sysinfo_fuse_c on macOS / macfuse_env.

Scoring (100 points, pass at 70):

     5 pts  C1   Project directory ~/Documents/sysinfo_fuse/ exists.
    10 pts  C2   sysinfo.c exists and is non-empty (> 200 bytes).
    15 pts  C3   sysinfo.c defines FUSE_USE_VERSION before #include of fuse.h.
                 - The macro define must appear at a smaller byte offset than
                   the first fuse.h include. Defining it *after* the include
                   has no effect (the header has already been preprocessed
                   against the default API version), so the verifier rejects
                   that ordering even though the macro nominally exists.
    10 pts  C4   sysinfo.c includes fuse.h (accepts <fuse.h>, "fuse.h", or
                 <fuse/fuse.h>).
    20 pts  C5   All 4 mandatory callbacks defined as functions
                 (getattr, readdir, open, read). Scored 5 pts per callback,
                 so a 3-of-4 partial scores 15.
    15 pts  C6   sysinfo.c calls sysctl or sysctlbyname at least twice.
                 Binary: ≥2 yields full credit; <2 yields zero.
    10 pts  C7   All 4 required virtual filenames appear as string literals
                 (cpu.txt, memory.txt, uptime.txt, hostname.txt). Scored
                 2.5 pts per filename — final per-criterion score rounded
                 down to nearest integer.
    10 pts  C8   Makefile exists with FUSE_USE_VERSION=26 define AND
                 pkg-config fuse usage. Scored 5 + 5 (define present;
                 pkg-config invocation present).
     5 pts  C9   Compiled binary `sysinfo_fuse` exists in the project dir
                 and is a Mach-O executable. Bonus — compilation actually
                 succeeded.

Partial credit ceiling (Anti-Pattern 4):
    The maximum score an agent can achieve without hitting any full
    criterion is bounded by the per-element fractions on C5 + C7 +
    half-Makefile on C8 + the file-existence credits on C1, C2:
      C1=5 + C2=10 + C5(3 of 4)=15 + C7(3 of 4)=7 + C8(1 of 2)=5 = 42
    42 < 70 pass threshold. ✓

Adversarial bound (do-nothing strategy enumeration, Anti-Pattern 13):
    Do-nothing: 0/100. The setup script wipes any pre-existing project
    directory, so no criterion is satisfied by the initial state.

Gates:
    - Gate 1 (no work): no project directory at all → score 0.
    - There is no strict wrong-target gate; an agent that authors a real
      macFUSE C file in the right directory but names different filenames
      is *partially* correct and scored accordingly. The C7 criterion (10
      pts) carries the filename discipline.

Read pattern: copy_from_env(/tmp/macfuse_sysinfo_fuse_c_result.json,
local_tmp) — produced by export_result.sh.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict


logger = logging.getLogger(__name__)

REMOTE_RESULT = "/tmp/macfuse_sysinfo_fuse_c_result.json"
PASS_THRESHOLD = 70
MIN_SOURCE_BYTES = 200
MIN_SYSCTL_CALLS = 2

REQUIRED_CALLBACKS = ("getattr", "readdir", "open", "read")
REQUIRED_FILENAMES = ("cpu.txt", "memory.txt", "uptime.txt", "hostname.txt")


def _empty_subscores() -> Dict[str, int]:
    return {
        "project_dir":      0,  # C1
        "source_nonempty":  0,  # C2
        "fuse_use_version": 0,  # C3
        "fuse_h_include":   0,  # C4
        "callbacks":        0,  # C5
        "sysctl":           0,  # C6
        "filenames":        0,  # C7
        "makefile":         0,  # C8
        "compiled_binary":  0,  # C9
    }


def verify_macfuse_sysinfo_fuse_c(
    traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]
) -> Dict[str, Any]:
    del traj
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"score": 0, "passed": False,
                "feedback": "env_info missing copy_from_env",
                "subscores": _empty_subscores()}

    metadata = (task_info or {}).get("metadata", {}) or {}
    pass_threshold = int(metadata.get("pass_threshold", PASS_THRESHOLD))
    min_source_bytes = int(metadata.get("min_source_bytes", MIN_SOURCE_BYTES))
    min_sysctl_calls = int(metadata.get("min_sysctl_calls", MIN_SYSCTL_CALLS))

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

    project_dir_exists = bool(data.get("project_dir_exists", False))
    source_exists = bool(data.get("source_exists", False))
    source_bytes = int(data.get("source_bytes", 0) or 0)
    makefile_exists = bool(data.get("makefile_exists", False))
    binary_exists = bool(data.get("binary_exists", False))
    binary_is_macho = bool(data.get("binary_is_macho", False))

    source_analysis = data.get("source_analysis", {}) or {}
    makefile_analysis = data.get("makefile_analysis", {}) or {}

    subscores = _empty_subscores()
    feedback: list[str] = []

    # ---- Gate 1: no project directory ----
    if not project_dir_exists:
        return {"score": 0, "passed": False,
                "feedback": "No project directory at ~/Documents/sysinfo_fuse/ — agent did not create the project.",
                "subscores": subscores}

    # ---- C1: project directory exists (5 pts) ----
    subscores["project_dir"] = 5
    feedback.append("Project directory exists (+5)")

    # ---- C2: source file non-empty (10 pts) ----
    if source_exists and source_bytes > min_source_bytes:
        subscores["source_nonempty"] = 10
        feedback.append(f"sysinfo.c exists, {source_bytes} bytes (>{min_source_bytes}) (+10)")
    elif source_exists:
        feedback.append(f"sysinfo.c exists but too small ({source_bytes} bytes <= {min_source_bytes}) (+0)")
    else:
        feedback.append("sysinfo.c missing (+0)")

    # ---- C3: FUSE_USE_VERSION before fuse.h include (15 pts) ----
    has_define = bool(source_analysis.get("has_fuse_use_version_define", False))
    define_before_include = bool(source_analysis.get("fuse_use_version_before_include", False))
    if has_define and define_before_include:
        subscores["fuse_use_version"] = 15
        v = source_analysis.get("fuse_use_version_value")
        feedback.append(f"FUSE_USE_VERSION defined (value={v}) before fuse.h include (+15)")
    elif has_define and not define_before_include:
        feedback.append("FUSE_USE_VERSION defined but AFTER fuse.h include — macro is a no-op there (+0)")
    else:
        feedback.append("FUSE_USE_VERSION not defined in sysinfo.c (+0)")

    # ---- C4: fuse.h include (10 pts) ----
    if source_analysis.get("has_fuse_h_include", False):
        subscores["fuse_h_include"] = 10
        feedback.append("sysinfo.c includes fuse.h (+10)")
    else:
        feedback.append("sysinfo.c does not include fuse.h (+0)")

    # ---- C5: 4 callbacks (5 pts each) ----
    callbacks = source_analysis.get("callbacks_defined", {}) or {}
    cb_credit = 0
    cb_hits = []
    cb_misses = []
    for cb in REQUIRED_CALLBACKS:
        if callbacks.get(cb, False):
            cb_credit += 5
            cb_hits.append(cb)
        else:
            cb_misses.append(cb)
    subscores["callbacks"] = cb_credit
    if cb_credit == 20:
        feedback.append(f"All 4 callbacks defined: {cb_hits} (+20)")
    elif cb_credit > 0:
        feedback.append(f"Callbacks defined: {cb_hits}; missing: {cb_misses} (+{cb_credit})")
    else:
        feedback.append(f"No FUSE callbacks defined; missing all: {list(REQUIRED_CALLBACKS)} (+0)")

    # ---- C6: sysctl call count >= 2 (15 pts) ----
    sysctl_count = int(source_analysis.get("sysctl_call_count", 0) or 0)
    if sysctl_count >= min_sysctl_calls:
        subscores["sysctl"] = 15
        feedback.append(f"{sysctl_count} sysctl/sysctlbyname call(s) (>={min_sysctl_calls}) (+15)")
    else:
        feedback.append(f"Only {sysctl_count} sysctl call(s); need >= {min_sysctl_calls} (+0)")

    # ---- C7: 4 filename literals (2.5 pts each, rounded down) ----
    filenames = source_analysis.get("filenames_present", {}) or {}
    fn_hits = []
    fn_misses = []
    for fn in REQUIRED_FILENAMES:
        if filenames.get(fn, False):
            fn_hits.append(fn)
        else:
            fn_misses.append(fn)
    # 4 hits → 10, 3 → 7, 2 → 5, 1 → 2, 0 → 0
    fn_table = {4: 10, 3: 7, 2: 5, 1: 2, 0: 0}
    fn_credit = fn_table[len(fn_hits)]
    subscores["filenames"] = fn_credit
    if fn_credit == 10:
        feedback.append(f"All 4 required virtual filenames present in source (+10)")
    elif fn_credit > 0:
        feedback.append(f"Filenames present: {fn_hits}; missing: {fn_misses} (+{fn_credit})")
    else:
        feedback.append(f"No required filenames present; missing: {list(REQUIRED_FILENAMES)} (+0)")

    # ---- C8: Makefile correctness (5 + 5) ----
    mk_credit = 0
    if makefile_exists:
        if makefile_analysis.get("has_fuse_use_version_26", False):
            mk_credit += 5
            feedback.append("Makefile defines FUSE_USE_VERSION=26 (+5)")
        else:
            feedback.append("Makefile missing FUSE_USE_VERSION=26 define (+0)")
        if makefile_analysis.get("has_pkg_config_fuse", False):
            mk_credit += 5
            feedback.append("Makefile uses pkg-config fuse (+5)")
        else:
            feedback.append("Makefile does not invoke pkg-config fuse (+0)")
    else:
        feedback.append("No Makefile at ~/Documents/sysinfo_fuse/Makefile (+0)")
    subscores["makefile"] = mk_credit

    # ---- C9: compiled binary (5 pts bonus) ----
    if binary_exists and binary_is_macho:
        subscores["compiled_binary"] = 5
        feedback.append("sysinfo_fuse Mach-O binary present — compilation succeeded (+5)")
    elif binary_exists:
        feedback.append("sysinfo_fuse file exists but is not a Mach-O executable (+0)")
    else:
        feedback.append("sysinfo_fuse binary not present — compilation did not succeed (+0)")

    total = sum(subscores.values())
    passed = total >= pass_threshold
    if passed:
        feedback.insert(0, f"PASSED ({total}/100, threshold {pass_threshold}): macFUSE sysinfo filesystem authored to specification.")
    else:
        feedback.insert(0, f"FAILED ({total}/100, threshold {pass_threshold}): macFUSE sysinfo filesystem incomplete.")
    return {"score": total, "passed": passed, "feedback": " | ".join(feedback), "subscores": subscores}
