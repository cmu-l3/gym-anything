"""Offline mock tests for verify_finder_running.

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/finder_env/tasks/launch_finder/test_verifier_offline.py

The smoke verifier is intentionally a thin layer over two shell signals:
  1. `pgrep -x 'Finder'`           → PIDs or empty
  2. `osascript ... count windows` → integer or "0"

…and combines them into a 0/50/100 score. There's no result-JSON read
path, so these tests stub `env_info["exec_capture"]` with a callable
that returns canned strings keyed on the command. Each scenario asserts
the expected (score, passed) tuple.

Required scenarios per task_creation_notes:
  - do-nothing equivalent (process not running)        → 0
  - partial-credit (process running, no window)        → 50
  - full-correct (process + window)                    → 100
  - edge / hardening (parseable-but-zero osascript)    → 50

Audit D2 (2026-05-18): added at the auditor's suggestion to bring the
smoke task into parity with the hard task's offline regression coverage.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path


HERE = Path(__file__).resolve().parent
VERIFIER_PATH = HERE / "verifier.py"
spec = importlib.util.spec_from_file_location("verifier", VERIFIER_PATH)
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
verify = mod.verify_finder_running


def make_exec_capture(responses: dict[str, str]):
    """Build a stub exec_capture that returns canned output for known commands.

    Matching is substring-based: the first key found in the issued command
    wins. Missing match → empty string (mirrors a quiet command).
    """
    def exec_capture(cmd: str) -> str:
        for key, value in responses.items():
            if key in cmd:
                return value
        return ""
    return exec_capture


def run(name: str, responses: dict[str, str], expect_score: int, expect_passed: bool) -> bool:
    env_info = {"exec_capture": make_exec_capture(responses)}
    out = verify(traj={}, env_info=env_info, task_info={})
    score = out["score"]; passed = out["passed"]
    score_ok = score == expect_score
    pass_ok = passed == expect_passed
    status = "PASS" if (score_ok and pass_ok) else "FAIL"
    print(f"[{status}] {name}: got score={score} passed={passed} "
          f"(expected score={expect_score} passed={expect_passed})")
    if not (score_ok and pass_ok):
        print(f"    feedback: {out.get('feedback')}")
        return False
    return True


# ---- Scenarios ---------------------------------------------------------

NO_FINDER = {
    # pgrep finds nothing (Finder somehow killed and not yet respawned);
    # osascript fails because there's no Finder to talk to and the shell
    # `|| echo '0'` fallback produces "0".
    "pgrep -x 'Finder'": "",
    "count windows": "0",
}
# Expected: process_running=False → 0 / failed.

FINDER_NO_WINDOW = {
    # Finder is running (launchd respawned it) but no window is open yet
    # (e.g., pre_task hasn't called `open <dir>` yet).
    "pgrep -x 'Finder'": "3627",
    "count windows": "0",
}
# Expected: process_running=True, window_count=0 → 50 / failed.

FINDER_WITH_ONE_WINDOW = {
    # Healthy state after pre_task: Finder running + one window registered.
    "pgrep -x 'Finder'": "3627",
    "count windows": "1",
}
# Expected: 100 / passed.

FINDER_WITH_MANY_WINDOWS = {
    # Multiple windows open (e.g., agent opened additional folders
    # during the trajectory). Still passes — the verifier just needs ≥1.
    "pgrep -x 'Finder'": "3627\n3628",
    "count windows": "3",
}
# Expected: 100 / passed.

OSASCRIPT_NOISE = {
    # osascript prints stderr noise but the last line is the count.
    # Verifier reads .splitlines()[-1] so it tolerates extra preamble.
    "pgrep -x 'Finder'": "3627",
    "count windows": "execution error: noise\n2",
}
# Expected: 100 / passed.

OSASCRIPT_UNPARSEABLE = {
    # osascript output isn't an integer at all (e.g., a full traceback).
    # The verifier's try/except falls back to window_count=0.
    "pgrep -x 'Finder'": "3627",
    "count windows": "Error: -25211 not authorized",
}
# Expected: 50 / failed.


if __name__ == "__main__":
    print("=== Offline verifier tests: launch_finder ===")
    results = [
        run("no-finder (process missing)",              NO_FINDER,              expect_score=0,   expect_passed=False),
        run("finder-no-window (process running, count=0)", FINDER_NO_WINDOW,    expect_score=50,  expect_passed=False),
        run("finder-with-one-window (healthy state)",   FINDER_WITH_ONE_WINDOW, expect_score=100, expect_passed=True),
        run("finder-with-many-windows (count=3)",       FINDER_WITH_MANY_WINDOWS, expect_score=100, expect_passed=True),
        run("osascript-noise (multi-line, count tail)", OSASCRIPT_NOISE,        expect_score=100, expect_passed=True),
        run("osascript-unparseable (falls back to 0)",  OSASCRIPT_UNPARSEABLE,  expect_score=50,  expect_passed=False),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
