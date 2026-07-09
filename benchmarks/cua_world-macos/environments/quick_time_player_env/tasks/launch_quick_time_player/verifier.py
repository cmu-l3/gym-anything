"""Smoke verifier for quick_time_player_env: passes when QuickTime Player is
running with a registered LaunchServices window. Uses pgrep + lsappinfo only
— no AX calls, so no TCC headaches over SSH.
"""

from __future__ import annotations

from typing import Any, Dict


def verify_quick_time_player_running(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    del traj, task_info
    exec_capture = env_info["exec_capture"]

    # pgrep -x matches the exact process name 'QuickTime Player' (with the
    # literal space). That avoids ever being fooled by helper processes that
    # don't actually share this exact name.
    pgrep_out = exec_capture("pgrep -x 'QuickTime Player' || true").strip()
    process_running = bool(pgrep_out)

    # QuickTime Player registers exactly one ASN with com.apple.QuickTimePlayerX
    # as its bundleID. Match on that key — robust regardless of the helper
    # processes present in the lsappinfo listing (the apple_notes pattern).
    # The bundle-path / display-name lines can be inconsistent across macOS
    # versions; bundleID is the canonical identifier.
    lsapp = exec_capture(
        "/usr/bin/lsappinfo list 2>/dev/null | grep -F 'bundleID=\"com.apple.QuickTimePlayerX\"' || true"
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
