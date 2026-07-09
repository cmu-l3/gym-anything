"""Offline mock tests for verify_preview_running.

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/preview_env/tasks/launch_preview/test_verifier_offline.py

The smoke verifier reads two shell outputs via env_info["exec_capture"]:
  1. `pgrep -x 'Preview' || true` → empty string if not running, pid(s) otherwise
  2. `/usr/bin/lsappinfo list 2>/dev/null | grep -iE 'Preview\\.app' || true`
     → empty string if no Preview bundle path registered, non-empty otherwise

Two scenarios cover the full pass/fail surface; a third covers the
half-state where the process exists but LaunchServices hasn't registered
the bundle yet (50/100, the documented partial-credit case).
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path


HERE = Path(__file__).resolve().parent
VERIFIER_PATH = HERE / "verifier.py"
spec = importlib.util.spec_from_file_location("verifier", VERIFIER_PATH)
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
verify = mod.verify_preview_running


def make_env_info(pgrep_out: str, lsapp_out: str) -> dict:
    def exec_capture(cmd: str) -> str:
        if "pgrep" in cmd:
            return pgrep_out
        if "lsappinfo" in cmd:
            return lsapp_out
        return ""
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
        print(f"    feedback: {out['feedback']}")
        return False
    return True


# Realistic lsappinfo bundle-path line; the verifier's regex matches Preview\.app
LSAPP_REGISTERED = 'bundle path="/System/Applications/Preview.app"\n'


if __name__ == "__main__":
    print("=== Offline verifier tests: launch_preview ===")
    results = [
        run("running + registered (full pass)",
            pgrep_out="966\n", lsapp_out=LSAPP_REGISTERED,
            expect_score=100, expect_passed=True),
        run("not running (clean fail)",
            pgrep_out="", lsapp_out="",
            expect_score=0, expect_passed=False),
        run("process exists but window not yet registered (partial)",
            pgrep_out="966\n", lsapp_out="",
            expect_score=50, expect_passed=False),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
