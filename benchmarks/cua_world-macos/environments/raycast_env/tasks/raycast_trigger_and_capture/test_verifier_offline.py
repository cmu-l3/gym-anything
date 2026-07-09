"""Offline mock tests for verify_raycast_trigger_and_capture.

Per task_creation_notes/13_file_content_verification_and_offline_testing.md:
required scenarios are do-nothing, wrong-target, partial, full-correct, plus
anti-gaming scenarios per task_creation_notes/14_task_design_antipatterns.md.

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/raycast_env/tasks/raycast_trigger_and_capture/test_verifier_offline.py

Each scenario injects a fabricated result dict (the shape produced by
export_result.sh) and asserts the verifier's score and pass decision.
Exits non-zero on any assertion failure.
"""

from __future__ import annotations

import importlib.util
import json
import shutil
import sys
import tempfile
from pathlib import Path


HERE = Path(__file__).resolve().parent
VERIFIER_PATH = HERE / "verifier.py"
spec = importlib.util.spec_from_file_location("verifier", VERIFIER_PATH)
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
verify = mod.verify_raycast_trigger_and_capture


def make_env_info(fake_result: dict) -> dict:
    fixture = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    fixture.write(json.dumps(fake_result).encode()); fixture.close()
    def copy_from_env(_remote: str, local: str) -> None:
        shutil.copy(fixture.name, local)
    return {"copy_from_env": copy_from_env, "_fixture": fixture.name}


def run(name: str, fake_result: dict, expect_score, expect_passed: bool) -> bool:
    env_info = make_env_info(fake_result)
    out = verify(traj={}, env_info=env_info, task_info={})
    Path(env_info["_fixture"]).unlink(missing_ok=True)
    score = out["score"]; passed = out["passed"]
    if isinstance(expect_score, tuple):
        lo, hi = expect_score
        score_ok = lo <= score <= hi
        expect_desc = f"{lo}..{hi}"
    else:
        score_ok = score == expect_score
        expect_desc = str(expect_score)
    pass_ok = passed == expect_passed
    status = "PASS" if (score_ok and pass_ok) else "FAIL"
    print(f"[{status}] {name}: got score={score} passed={passed} "
          f"(expected score={expect_desc} passed={expect_passed})")
    if not (score_ok and pass_ok):
        print(f"    subscores: {out['subscores']}")
        print(f"    feedback:  {out['feedback']}")
        return False
    return True


TASK_START = 1_000_000
SCREENSHOT_PATH = "/Users/lume/Desktop/raycast_screenshot.png"


DO_NOTHING = {
    "task_start": TASK_START,
    "initial_wal_size_bytes": 156592,
    "screenshot_path": SCREENSHOT_PATH,
    "screenshot_exists": False,
    "screenshot_mtime": 0,
    "screenshot_size_bytes": 0,
    "screenshot_is_screencapture": False,
    "wal_size_bytes": 156592,
    "wal_size_delta_bytes": 0,
    "raycast_still_running": True,
}

# Wrong-target: agent screenshot the desktop with Cmd+Shift+3 (which DOES
# add the screencapture xattr) but never actually invoked any Raycast URL.
# The export records the screenshot but the WAL delta is essentially zero.
# Strict wrong-target gate fires \u2192 score 0.
WRONG_TARGET_SCREENSHOT_ONLY = {
    "task_start": TASK_START,
    "initial_wal_size_bytes": 156592,
    "screenshot_path": SCREENSHOT_PATH,
    "screenshot_exists": True,
    "screenshot_mtime": TASK_START + 30,
    "screenshot_size_bytes": 1_500_000,
    "screenshot_is_screencapture": True,
    "wal_size_bytes": 156820,        # +228 bytes from background activity
    "wal_size_delta_bytes": 228,
    "raycast_still_running": True,
}

# Wrong-target variant: agent moved an unrelated PNG into the deliverable
# path with `mv unrelated.png ~/Desktop/raycast_screenshot.png`. File
# exists but lacks the screencapture xattr AND Raycast was never triggered.
WRONG_TARGET_NO_XATTR_NO_RAYCAST = {
    "task_start": TASK_START,
    "initial_wal_size_bytes": 156592,
    "screenshot_path": SCREENSHOT_PATH,
    "screenshot_exists": True,
    "screenshot_mtime": TASK_START + 60,
    "screenshot_size_bytes": 500_000,
    "screenshot_is_screencapture": False,
    "wal_size_bytes": 156700,
    "wal_size_delta_bytes": 108,
    "raycast_still_running": True,
}

# Partial: agent triggered Raycast (WAL grew) but never saved a screenshot.
# C4 = 50; pass threshold is 60, so partial is below pass.
PARTIAL_RAYCAST_NO_SCREENSHOT = {
    "task_start": TASK_START,
    "initial_wal_size_bytes": 156592,
    "screenshot_path": SCREENSHOT_PATH,
    "screenshot_exists": False,
    "screenshot_mtime": 0,
    "screenshot_size_bytes": 0,
    "screenshot_is_screencapture": False,
    "wal_size_bytes": 159500,
    "wal_size_delta_bytes": 2908,
    "raycast_still_running": True,
}

# Partial 2: agent triggered Raycast AND saved a screenshot, but the file
# lacks the screencapture xattr (e.g., they used `cp /some/other.png` or
# generated it with a non-screencapture tool). C1+C2+C4 = 15+15+50 = 80.
PARTIAL_NO_XATTR = {
    "task_start": TASK_START,
    "initial_wal_size_bytes": 156592,
    "screenshot_path": SCREENSHOT_PATH,
    "screenshot_exists": True,
    "screenshot_mtime": TASK_START + 30,
    "screenshot_size_bytes": 1_200_000,
    "screenshot_is_screencapture": False,
    "wal_size_bytes": 161500,
    "wal_size_delta_bytes": 4908,
    "raycast_still_running": True,
}

# Partial 3: agent triggered Raycast and the screenshot exists with xattr,
# but the screenshot mtime is BEFORE task_start (e.g., a stale file the
# pre_task delete missed somehow). C1+C3+C4 = 15+20+50 = 85.
PARTIAL_STALE_SCREENSHOT = {
    "task_start": TASK_START,
    "initial_wal_size_bytes": 156592,
    "screenshot_path": SCREENSHOT_PATH,
    "screenshot_exists": True,
    "screenshot_mtime": TASK_START - 100,
    "screenshot_size_bytes": 800_000,
    "screenshot_is_screencapture": True,
    "wal_size_bytes": 162000,
    "wal_size_delta_bytes": 5408,
    "raycast_still_running": True,
}

# Full correct: every criterion fires. 15+15+20+50 = 100.
FULL_CORRECT = {
    "task_start": TASK_START,
    "initial_wal_size_bytes": 156592,
    "screenshot_path": SCREENSHOT_PATH,
    "screenshot_exists": True,
    "screenshot_mtime": TASK_START + 25,
    "screenshot_size_bytes": 1_400_000,
    "screenshot_is_screencapture": True,
    "wal_size_bytes": 161800,
    "wal_size_delta_bytes": 5208,
    "raycast_still_running": True,
}

# Edge case: WAL grew JUST below threshold (background spike). Should still
# trip wrong-target gate when screenshot exists.
EDGE_WAL_JUST_BELOW_THRESHOLD = {
    "task_start": TASK_START,
    "initial_wal_size_bytes": 156592,
    "screenshot_path": SCREENSHOT_PATH,
    "screenshot_exists": True,
    "screenshot_mtime": TASK_START + 30,
    "screenshot_size_bytes": 1_500_000,
    "screenshot_is_screencapture": True,
    "wal_size_bytes": 156592 + 1023,  # 1 byte below 1024 threshold
    "wal_size_delta_bytes": 1023,
    "raycast_still_running": True,
}

# Edge case: WAL grew JUST at threshold \u2014 should count as trigger and
# (with full screenshot) → 100.
EDGE_WAL_AT_THRESHOLD = {
    "task_start": TASK_START,
    "initial_wal_size_bytes": 156592,
    "screenshot_path": SCREENSHOT_PATH,
    "screenshot_exists": True,
    "screenshot_mtime": TASK_START + 30,
    "screenshot_size_bytes": 1_500_000,
    "screenshot_is_screencapture": True,
    "wal_size_bytes": 156592 + 1024,
    "wal_size_delta_bytes": 1024,
    "raycast_still_running": True,
}


if __name__ == "__main__":
    print("=== Offline verifier tests: raycast_trigger_and_capture ===")
    results = [
        run("do-nothing",
            DO_NOTHING,                     expect_score=0,   expect_passed=False),
        run("wrong-target (screenshot only, no Raycast)",
            WRONG_TARGET_SCREENSHOT_ONLY,   expect_score=0,   expect_passed=False),
        run("wrong-target (moved PNG, no Raycast)",
            WRONG_TARGET_NO_XATTR_NO_RAYCAST, expect_score=0, expect_passed=False),
        run("partial (Raycast triggered, no screenshot)",
            PARTIAL_RAYCAST_NO_SCREENSHOT,  expect_score=50,  expect_passed=False),
        run("partial (Raycast + screenshot, no xattr)",
            PARTIAL_NO_XATTR,               expect_score=80,  expect_passed=True),
        run("partial (Raycast + xattr screenshot, stale mtime)",
            PARTIAL_STALE_SCREENSHOT,       expect_score=85,  expect_passed=True),
        run("full-correct (everything)",
            FULL_CORRECT,                   expect_score=100, expect_passed=True),
        run("edge: WAL just below threshold (wrong-target gate fires)",
            EDGE_WAL_JUST_BELOW_THRESHOLD,  expect_score=0,   expect_passed=False),
        run("edge: WAL exactly at threshold (gate doesn't fire)",
            EDGE_WAL_AT_THRESHOLD,          expect_score=100, expect_passed=True),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
