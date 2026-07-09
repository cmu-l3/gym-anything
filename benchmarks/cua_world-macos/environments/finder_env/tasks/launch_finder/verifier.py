"""Smoke verifier for finder_env: passes when Finder is running AND at
least one Finder window is open.

Finder is the macOS shell — `pgrep -x Finder` is essentially always
positive on a healthy image (launchd respawns Finder if killed). So the
process check alone is a weak signal. We additionally count open Finder
windows via AppleEvents (`tell application "Finder" to count windows`),
which goes through Automation TCC, not Accessibility TCC, and works over
SSH in practice (verified against safari_env's evidence_docs that AppleEvent
commands without AX walks succeed where System Events walks fail).

Scoring:
  100: process running AND ≥1 window
   50: process running but no window (Finder is up but nothing was opened)
    0: process not running (broken sandbox state)
"""

from __future__ import annotations

from typing import Any, Dict


def verify_finder_running(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    del traj, task_info
    exec_capture = env_info["exec_capture"]

    pgrep_out = exec_capture("pgrep -x 'Finder' || true").strip()
    process_running = bool(pgrep_out)

    # Count open Finder windows. AppleEvent to Finder (not System Events
    # AX walk) — works over SSH per the safari_env evidence.
    count_raw = exec_capture(
        "osascript -e 'tell application \"Finder\" to count windows' 2>/dev/null || echo '0'"
    ).strip()
    try:
        window_count = int(count_raw.splitlines()[-1])
    except (ValueError, IndexError):
        window_count = 0
    window_open = window_count >= 1

    passed = process_running and window_open
    return {
        "passed": passed,
        "score": 100 if passed else (50 if process_running else 0),
        "feedback": (
            f"process_running={process_running}"
            + (f" (pids: {pgrep_out})" if pgrep_out else "")
            + f"; window_count={window_count}"
        ),
    }
