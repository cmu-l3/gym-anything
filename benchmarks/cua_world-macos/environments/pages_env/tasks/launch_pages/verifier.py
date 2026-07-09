"""Smoke verifier for pages_env: passes when Apple Pages is running with a
registered LaunchServices window. Uses pgrep + lsappinfo only \u2014 no AX
calls, so no TCC headaches over SSH.
"""

from __future__ import annotations

from typing import Any, Dict


def verify_pages_running(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    del traj, task_info
    exec_capture = env_info["exec_capture"]

    # pgrep -x matches the exact process name 'Pages' so we don't get fooled
    # by helpers or any other process whose command line mentions "pages".
    pgrep_out = exec_capture("pgrep -x 'Pages' || true").strip()
    process_running = bool(pgrep_out)

    # Pages registers exactly one ASN with `com.apple.iWork.Pages` as its
    # bundleID; matching that line is unambiguous.
    lsapp = exec_capture(
        "/usr/bin/lsappinfo list 2>/dev/null | grep -F 'bundleID=\"com.apple.iWork.Pages\"' || true"
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
