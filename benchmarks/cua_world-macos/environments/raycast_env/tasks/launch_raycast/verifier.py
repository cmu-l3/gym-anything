"""Smoke verifier for raycast_env: passes when Raycast is running with a
registered LaunchServices entry. Uses pgrep + lsappinfo only \u2014 no AX over
SSH (TCC blocks `osascript ... tell System Events` per
12_macos_environments.md).

Detection strategy:
  - pgrep -x 'Raycast' matches the exact main-process name. Raycast does
    not spin off helper subprocesses with `Raycast` substring (unlike
    Notion's `Notion Helper`), so -x is sufficient.
  - lsappinfo list is grepped for the bundle path ('Raycast.app'). This
    is the helper-free pattern from 12_macos_environments.md ("lsappinfo
    Regex: Helper-Free Apps Need a Different Pattern") \u2014 the bundle-path
    line is emitted exactly when LaunchServices has registered the app.
"""

from __future__ import annotations

from typing import Any, Dict


def verify_raycast_running(
    traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]
) -> Dict[str, Any]:
    del traj, task_info
    exec_capture = env_info["exec_capture"]

    # pgrep -x matches the exact process name 'Raycast'. There are no
    # short-named helpers to worry about for Raycast.
    pgrep_out = exec_capture("pgrep -x 'Raycast' || true").strip()
    process_running = bool(pgrep_out)

    # Match the bundle path emitted by `lsappinfo list` (e.g.
    # `bundle path="/Applications/Raycast.app"`). This is the helper-free
    # detection pattern from specific_env_notes/preview/ \u2014 fires only when
    # LaunchServices has fully registered the app.
    lsapp = exec_capture(
        "/usr/bin/lsappinfo list 2>/dev/null | grep -iE 'Raycast\\.app' || true"
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
