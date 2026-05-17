"""Smoke verifier for notion_env: passes when Notion is running with a
registered LaunchServices window. Uses pgrep + lsappinfo only — no AX over
SSH (TCC blocks `osascript ... tell System Events` per
12_macos_environments.md).
"""

from __future__ import annotations

from typing import Any, Dict


def verify_notion_running(
    traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]
) -> Dict[str, Any]:
    del traj, task_info
    exec_capture = env_info["exec_capture"]

    # pgrep -x matches the exact process name 'Notion'. Notion's helper
    # processes are named 'Notion Helper' / 'Notion Helper (GPU)' / etc.,
    # which '-x Notion' correctly excludes.
    pgrep_out = exec_capture("pgrep -x 'Notion' || true").strip()
    process_running = bool(pgrep_out)

    # lsappinfo reports launched apps via LaunchServices. The bundle name
    # 'Notion' appears in quotes in the list output (with helpers as
    # separate entries: "Notion Helper", "Notion Helper (GPU)"). Use a
    # quoted, word-boundary grep so helpers don't satisfy the check.
    lsapp = exec_capture(
        "/usr/bin/lsappinfo list 2>/dev/null | grep -E '\"Notion\"' || true"
    )
    window_registered = bool((lsapp or "").strip())

    passed = process_running and window_registered
    return {
        "passed": passed,
        "score": 100 if passed else (50 if process_running else 0),
        "feedback": (
            f"process_running={process_running}"
            + (f" (pids: {pgrep_out})" if pgrep_out else "")
            + f"; window_registered={window_registered}"
        ),
    }
