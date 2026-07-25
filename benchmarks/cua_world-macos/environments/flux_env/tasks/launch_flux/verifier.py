"""Smoke verifier for flux_env: passes when f.lux is running with the bundle
registered in LaunchServices. Uses pgrep + lsappinfo only — no AX calls,
so no TCC headaches over SSH.

Notes:
- f.lux is a menu-bar agent (LSUIElement=true); it has no Dock icon and
  does not open a regular window. The verifier therefore does NOT check
  for a window — just process + LaunchServices registration.
- f.lux is helper-free (no Sparkle helper process, no Flux Web Content
  etc.), so the safari-style `Flux( |$)` word-boundary regex never matches.
  Use the bundle-path pattern (`Flux\\.app`) from the preview_env lesson
  in 12_macos_environments.md instead.
"""

from __future__ import annotations

from typing import Any, Dict


def verify_flux_running(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    del traj, task_info
    exec_capture = env_info["exec_capture"]

    pgrep_out = exec_capture("pgrep -x 'Flux' || true").strip()
    process_running = bool(pgrep_out)

    lsapp = exec_capture(
        "/usr/bin/lsappinfo list 2>/dev/null | grep -iE 'Flux\\.app' || true"
    )
    ls_registered = bool((lsapp or "").strip())

    passed = process_running and ls_registered
    return {
        "passed": passed,
        "score": 100 if passed else (50 if process_running else 0),
        "feedback": (
            f"process_running={process_running}"
            + (f" (pids: {pgrep_out})" if pgrep_out else "")
            + f"; ls_registered={ls_registered}"
        ),
    }
