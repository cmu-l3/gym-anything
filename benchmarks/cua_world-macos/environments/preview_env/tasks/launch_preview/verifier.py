"""Smoke verifier for preview_env: passes when Preview is running with a
registered LaunchServices window. Uses pgrep + lsappinfo only — no AX
calls, so no TCC headaches over SSH.
"""

from __future__ import annotations

from typing import Any, Dict


def verify_preview_running(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    del traj, task_info
    exec_capture = env_info["exec_capture"]

    # pgrep -x matches the exact process name 'Preview' so we don't get fooled
    # by anything named "PreviewXPC" or similar.
    pgrep_out = exec_capture("pgrep -x 'Preview' || true").strip()
    process_running = bool(pgrep_out)

    # Preview's lsappinfo entry is `"Preview" ASN:0x0-...` — the closing `"`
    # right after Preview means the safari-style pattern `'Preview( |$)'`
    # doesn't match (it relied on helper entries like `"Safari Networking"`
    # where Preview-style apps don't have any). Match the bundle-path
    # line instead: lsappinfo always includes `bundle path=".../Preview.app"`
    # for a registered Preview process.
    lsapp = exec_capture(
        "/usr/bin/lsappinfo list 2>/dev/null | grep -iE 'Preview\\.app' || true"
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
