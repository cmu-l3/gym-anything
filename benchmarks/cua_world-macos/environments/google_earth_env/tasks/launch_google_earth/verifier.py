"""Verifier for the launch_google_earth task.

Passes when Google Earth Pro is running AND has registered itself with
LaunchServices as a foreground app (proxy for "the window is up", since
the actual AX tree is gated by TCC over SSH and can't be probed without
the use.computer ax_helper).
"""

from __future__ import annotations

from typing import Any, Dict


def verify_google_earth_running(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    del traj, task_info  # not needed; we check live process state
    exec_capture = env_info["exec_capture"]

    pgrep_out = exec_capture("pgrep -f 'Google Earth Pro' || true").strip()
    process_running = bool(pgrep_out)

    # lsappinfo reports launched apps without needing Accessibility — if Google
    # Earth Pro has registered itself with LaunchServices, it has a window.
    lsapp = exec_capture(
        "/usr/bin/lsappinfo list 2>/dev/null | grep -i 'Google Earth' || true"
    )
    window_registered = bool((lsapp or "").strip())

    passed = process_running and window_registered
    score = 100 if passed else (50 if process_running else 0)
    feedback = (
        f"process_running={process_running}"
        + (f" (pids: {pgrep_out})" if pgrep_out else "")
        + f"; window_registered={window_registered}"
    )
    return {"passed": passed, "score": score, "feedback": feedback}
