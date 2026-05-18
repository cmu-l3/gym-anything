"""Offline mock tests for verify_home_office_productivity.

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/system_settings_env/tasks/home_office_productivity/test_verifier_offline.py
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
verify = mod.verify_home_office_productivity


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


def res(*, auto_appearance=False, scrollbars="Automatic", ui_sound_feedback=1,
        dock_show_recents=True, dock_mineffect="genie") -> dict:
    return {
        "task_start": TASK_START,
        "auto_appearance": auto_appearance,
        "scrollbars": scrollbars,
        "ui_sound_feedback": ui_sound_feedback,
        "dock_show_recents": dock_show_recents,
        "dock_mineffect": dock_mineffect,
        "read_errors": [],
    }


DO_NOTHING = res()

# Wrong scroll bars ("WhenScrolling") — no full credits → gate fires.
WRONG_SCROLLBARS = res(scrollbars="WhenScrolling")

# Wrong minimize effect ("suck") — no full credits → gate fires.
WRONG_MINEFFECT = res(dock_mineffect="suck")

# 3 of 5 correct = 60 — threshold edge.
THREE_OF_FIVE = res(auto_appearance=True, scrollbars="Always", ui_sound_feedback=0)

# 4 of 5 correct = 80.
FOUR_OF_FIVE = res(auto_appearance=True, scrollbars="Always", ui_sound_feedback=0,
                   dock_show_recents=False)

# All 5 correct = 100.
FULL_CORRECT = res(auto_appearance=True, scrollbars="Always", ui_sound_feedback=0,
                   dock_show_recents=False, dock_mineffect="scale")

# 2 of 5 correct (auto + sounds) = 40 — fails.
PARTIAL_2_OF_5 = res(auto_appearance=True, ui_sound_feedback=0)

# Wrong scroll bars + one full credit (auto=True) — no gate, score = 20.
WRONG_SCROLLBARS_PLUS_ONE_FULL = res(auto_appearance=True, scrollbars="WhenScrolling")


if __name__ == "__main__":
    print("=== Offline verifier tests: home_office_productivity ===")
    results = [
        run("do-nothing",                                         DO_NOTHING,                     expect_score=0,   expect_passed=False),
        run("wrong scroll bars — gate fires",                     WRONG_SCROLLBARS,               expect_score=0,   expect_passed=False),
        run("wrong mineffect — gate fires",                       WRONG_MINEFFECT,                expect_score=0,   expect_passed=False),
        run("3/5 correct (threshold edge, 60)",                   THREE_OF_FIVE,                  expect_score=60,  expect_passed=True),
        run("4/5 correct (80)",                                   FOUR_OF_FIVE,                   expect_score=80,  expect_passed=True),
        run("all 5 correct (100)",                                FULL_CORRECT,                   expect_score=100, expect_passed=True),
        run("2/5 correct (40, fails)",                            PARTIAL_2_OF_5,                 expect_score=40,  expect_passed=False),
        run("wrong scrollbars + 1 full (20, no gate)",            WRONG_SCROLLBARS_PLUS_ONE_FULL, expect_score=20,  expect_passed=False),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
