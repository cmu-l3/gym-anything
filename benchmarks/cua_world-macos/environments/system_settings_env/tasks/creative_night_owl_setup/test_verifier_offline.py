"""Offline mock tests for verify_creative_night_owl_setup.

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/system_settings_env/tasks/creative_night_owl_setup/test_verifier_offline.py
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
verify = mod.verify_creative_night_owl_setup


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


def res(*, reduce_motion=False, key_repeat=6, initial_key_repeat=25,
        hot_corner_bottom_left=0, hot_corner_top_right=0) -> dict:
    return {
        "task_start": TASK_START,
        "reduce_motion": reduce_motion,
        "key_repeat": key_repeat,
        "initial_key_repeat": initial_key_repeat,
        "hot_corner_bottom_left": hot_corner_bottom_left,
        "hot_corner_top_right": hot_corner_top_right,
        "read_errors": [],
    }


DO_NOTHING = res()

# Both sliders moved but not to target — strict gate fires (all partial, no full).
SLIDERS_PARTIAL_ONLY = res(key_repeat=3, initial_key_repeat=20)

# Reduce motion only = 20 pts — below threshold, no gate.
REDUCE_MOTION_ONLY = res(reduce_motion=True)

# 3 of 5 correct: motion + fast repeat + short delay = 20+25+25 = 70.
THREE_OF_FIVE = res(reduce_motion=True, key_repeat=2, initial_key_repeat=15)

# Partial repeat + correct initial = 10+25 = 35, no strict gate (1 full).
PARTIAL_REPEAT_FULL_INITIAL = res(initial_key_repeat=15, key_repeat=4)

# 4 of 5 correct: motion + both sliders + one corner = 20+25+25+15 = 85.
FOUR_OF_FIVE = res(reduce_motion=True, key_repeat=2, initial_key_repeat=15,
                   hot_corner_bottom_left=4)

# All 5 correct = 100.
FULL_CORRECT = res(reduce_motion=True, key_repeat=2, initial_key_repeat=15,
                   hot_corner_bottom_left=4, hot_corner_top_right=2)

# Wrong hot corner (screen saver=5, not Desktop=4) + nothing else.
WRONG_HOT_CORNER = res(hot_corner_bottom_left=5)


if __name__ == "__main__":
    print("=== Offline verifier tests: creative_night_owl_setup ===")
    results = [
        run("do-nothing",                                     DO_NOTHING,                  expect_score=0,   expect_passed=False),
        run("partial sliders only — strict gate fires",       SLIDERS_PARTIAL_ONLY,        expect_score=0,   expect_passed=False),
        run("reduce motion only (20, fails)",                 REDUCE_MOTION_ONLY,          expect_score=20,  expect_passed=False),
        run("3/5 correct (70, passes)",                       THREE_OF_FIVE,               expect_score=70,  expect_passed=True),
        run("partial repeat + full initial (35, fails)",      PARTIAL_REPEAT_FULL_INITIAL, expect_score=35,  expect_passed=False),
        run("4/5 correct (85, passes)",                       FOUR_OF_FIVE,                expect_score=85,  expect_passed=True),
        run("all 5 correct (100)",                            FULL_CORRECT,                expect_score=100, expect_passed=True),
        run("wrong hot corner — strict gate fires",           WRONG_HOT_CORNER,            expect_score=0,   expect_passed=False),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
