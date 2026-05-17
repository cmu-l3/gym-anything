"""Smoke verifier for safari_env: passes when Safari is running with a
registered LaunchServices window. Uses pgrep + lsappinfo only — no AX
calls, so no TCC headaches over SSH.
"""

from __future__ import annotations

from typing import Any, Dict


def verify_safari_running(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    del traj, task_info
    exec_capture = env_info["exec_capture"]

    # pgrep -x matches the exact process name 'Safari' so we don't get fooled
    # by helpers like SafariLinkExtension that share the bundle path.
    pgrep_out = exec_capture("pgrep -x 'Safari' || true").strip()
    process_running = bool(pgrep_out)

    lsapp = exec_capture(
        "/usr/bin/lsappinfo list 2>/dev/null | grep -iE 'Safari( |$)' || true"
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
