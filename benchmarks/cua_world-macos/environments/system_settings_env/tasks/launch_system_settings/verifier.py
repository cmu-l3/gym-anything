"""Smoke verifier for system_settings_env: passes when System Settings is
running with a registered LaunchServices window. Uses pgrep + lsappinfo
only — no AX calls, so no TCC headaches over SSH.
"""

from __future__ import annotations

from typing import Any, Dict


def verify_system_settings_running(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    del traj, task_info
    exec_capture = env_info["exec_capture"]

    # pgrep -x matches the exact process name "System Settings" (with the
    # space — the app's binary is at .../Contents/MacOS/System Settings).
    pgrep_out = exec_capture("pgrep -x 'System Settings' || true").strip()
    process_running = bool(pgrep_out)

    # System Settings is helper-free (no SystemSettingsLinkExtension etc.),
    # so the Safari-style `'System Settings'( |$)` regex won't match. Match
    # the bundle-path line in lsappinfo instead — present iff LaunchServices
    # registered a window for the process (cf. preview_env's verifier).
    lsapp = exec_capture(
        "/usr/bin/lsappinfo list 2>/dev/null | grep -iE 'System Settings\\.app' || true"
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
