"""Offline mock tests for verify_quick_time_player_running.

The smoke verifier is a 2-signal AND check (pgrep + lsappinfo). There are
only three meaningful states:

  - both match    → score 100, passed
  - pgrep only    → score 50, partial (process alive but window not registered;
                    AppKit/launchd is mid-launch, transient)
  - neither       → score 0, failed (QuickTime not running or crashed)

This file mocks env_info["exec_capture"] with a dict of canned responses
and asserts the verifier returns the expected score for each path.

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/quick_time_player_env/tasks/launch_quick_time_player/test_verifier_offline.py

Exits non-zero on any assertion failure so CI can gate on it.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path


HERE = Path(__file__).resolve().parent
VERIFIER_PATH = HERE / "verifier.py"
spec = importlib.util.spec_from_file_location("verifier", VERIFIER_PATH)
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
verify = mod.verify_quick_time_player_running


def make_env_info(pgrep_out: str, lsapp_out: str) -> dict:
    """Build an env_info dict whose exec_capture serves the canned outputs.

    The verifier issues exactly two exec_capture() calls, in this order:
      1. `pgrep -x 'QuickTime Player' || true`
      2. `/usr/bin/lsappinfo list … | grep -F 'bundleID="com.apple.QuickTimePlayerX"' || true`

    Our mock matches each call by substring so it stays robust to minor
    wording changes in the verifier.
    """
    def exec_capture(cmd: str) -> str:
        if "pgrep" in cmd:
            return pgrep_out
        if "lsappinfo" in cmd:
            return lsapp_out
        raise AssertionError(f"verifier issued unexpected exec_capture: {cmd!r}")
    return {"exec_capture": exec_capture}


def run(name: str, pgrep_out: str, lsapp_out: str, expect_score: int, expect_passed: bool) -> bool:
    env_info = make_env_info(pgrep_out, lsapp_out)
    out = verify(traj={}, env_info=env_info, task_info={})
    score = out["score"]; passed = out["passed"]
    score_ok = score == expect_score
    pass_ok = passed == expect_passed
    status = "PASS" if (score_ok and pass_ok) else "FAIL"
    print(f"[{status}] {name}: got score={score} passed={passed} "
          f"(expected score={expect_score} passed={expect_passed})")
    if not (score_ok and pass_ok):
        print(f"    feedback:  {out['feedback']}")
        return False
    return True


# Canned outputs that match the shape pgrep/lsappinfo actually emit on the
# use.computer dev fleet (cross-checked against live evidence in
# evidence_docs/launch_quick_time_player/live_smoke/).
PGREP_RUNNING = "20894\n"     # the actual PID observed in the live smoke run
PGREP_NOT_RUNNING = ""        # `|| true` swallows pgrep's exit 1, output stays empty

LSAPP_REGISTERED = (
    '    bundleID="com.apple.QuickTimePlayerX"\n'
    '    bundle path="/System/Applications/QuickTime Player.app"\n'
)
LSAPP_NOT_REGISTERED = ""


if __name__ == "__main__":
    print("=== Offline verifier tests: launch_quick_time_player ===")
    results = [
        run("both match — app running with registered window",
            PGREP_RUNNING, LSAPP_REGISTERED, expect_score=100, expect_passed=True),
        run("pgrep only — process up but window not yet registered",
            PGREP_RUNNING, LSAPP_NOT_REGISTERED, expect_score=50, expect_passed=False),
        run("neither — app not running at all",
            PGREP_NOT_RUNNING, LSAPP_NOT_REGISTERED, expect_score=0, expect_passed=False),
        run("lsapp without pgrep — defensive impossible state",
            PGREP_NOT_RUNNING, LSAPP_REGISTERED, expect_score=0, expect_passed=False),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
