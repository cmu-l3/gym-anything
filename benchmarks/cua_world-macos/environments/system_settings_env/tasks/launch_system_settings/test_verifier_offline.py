"""Offline mock tests for verify_system_settings_running.

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/system_settings_env/tasks/launch_system_settings/test_verifier_offline.py

The verifier shells out via `env_info["exec_capture"]`, so we mock that
callable with fabricated stdout strings for the various states the live
sandbox can return.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path


HERE = Path(__file__).resolve().parent
VERIFIER_PATH = HERE / "verifier.py"
spec = importlib.util.spec_from_file_location("verifier", VERIFIER_PATH)
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
verify = mod.verify_system_settings_running


def make_env_info(pgrep_out: str, lsapp_out: str) -> dict:
    """Build an env_info with a fake exec_capture that routes by command substring."""
    def exec_capture(cmd: str) -> str:
        if "pgrep" in cmd:
            return pgrep_out
        if "lsappinfo" in cmd:
            return lsapp_out
        return ""
    return {"exec_capture": exec_capture}


def run(name: str, pgrep_out: str, lsapp_out: str, expect_score: int, expect_passed: bool) -> bool:
    out = verify(traj={}, env_info=make_env_info(pgrep_out, lsapp_out), task_info={})
    score, passed = out["score"], out["passed"]
    ok = (score == expect_score) and (passed == expect_passed)
    status = "PASS" if ok else "FAIL"
    print(f"[{status}] {name}: got score={score} passed={passed} "
          f"(expected score={expect_score} passed={expect_passed})")
    if not ok:
        print(f"    feedback: {out['feedback']}")
        return False
    return True


# Live `pgrep -x 'System Settings'` returns the PID on stdout if running, "" otherwise.
PGREP_RUNNING = "806\n"
PGREP_ABSENT = ""

# Live `lsappinfo list | grep -iE 'System Settings\\.app'` returns the bundle-path
# lines when LaunchServices has the app registered, "" otherwise. The exact
# lines observed on the use.computer dev fleet (macOS 15.0).
LSAPP_REGISTERED = (
    '    bundle path="/System/Applications/System Settings.app"\n'
    '    executable path="/System/Applications/System Settings.app/Contents/MacOS/System Settings"\n'
    '    bundle path="/System/Applications/System Settings.app/Contents/PlugIns/GeneralSettings.appex"\n'
    '    executable path="/System/Applications/System Settings.app/Contents/PlugIns/GeneralSettings.appex/Contents/MacOS/GeneralSettings"\n'
)
LSAPP_NOT_REGISTERED = ""


if __name__ == "__main__":
    print("=== Offline verifier tests: launch_system_settings ===")
    results = [
        # Happy path: pre_task launched the app, lsappinfo registered.
        run("running + window registered (smoke pass)",
            PGREP_RUNNING, LSAPP_REGISTERED,
            expect_score=100, expect_passed=True),
        # Process running but no LaunchServices registration yet — partial.
        run("process up but window not yet registered",
            PGREP_RUNNING, LSAPP_NOT_REGISTERED,
            expect_score=50, expect_passed=False),
        # Nothing running — pre_task hook never ran or app died.
        run("nothing running",
            PGREP_ABSENT, LSAPP_NOT_REGISTERED,
            expect_score=0, expect_passed=False),
        # Edge case: lsappinfo somehow has the bundle line but pgrep returned
        # empty (e.g. helper appex registered without main binary). The verifier
        # requires BOTH signals — must not pass on lsappinfo alone.
        run("lsappinfo registered but pgrep empty",
            PGREP_ABSENT, LSAPP_REGISTERED,
            expect_score=0, expect_passed=False),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
