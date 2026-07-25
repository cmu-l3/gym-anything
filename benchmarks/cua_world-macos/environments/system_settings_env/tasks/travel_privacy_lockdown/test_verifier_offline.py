"""Offline mock tests for verify_travel_privacy_lockdown.

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/system_settings_env/tasks/travel_privacy_lockdown/test_verifier_offline.py
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
verify = mod.verify_travel_privacy_lockdown


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


def res(*, appearance=None, screensaver_idle_time=300, screensaver_ask_password=0,
        screensaver_password_delay=5, hot_corner_top_left=0) -> dict:
    return {
        "task_start": TASK_START,
        "appearance": appearance,
        "screensaver_idle_time": screensaver_idle_time,
        "screensaver_ask_password": screensaver_ask_password,
        "screensaver_password_delay": screensaver_password_delay,
        "hot_corner_top_left": hot_corner_top_left,
        "read_errors": [],
    }


DO_NOTHING = res()

# Screensaver set to 240s (partial, > 120) — only change, no full credit → gate fires.
PARTIAL_TIMEOUT_ONLY = res(screensaver_idle_time=240)

# Dark + password + immediate = 20+20+20 = 60 — threshold edge.
THREE_OF_FIVE = res(appearance="Dark", screensaver_ask_password=1, screensaver_password_delay=0)

# Dark + tight timeout + password + immediate = 80.
FOUR_OF_FIVE = res(appearance="Dark", screensaver_idle_time=60,
                   screensaver_ask_password=1, screensaver_password_delay=0)

# All 5 correct = 100.
FULL_CORRECT = res(appearance="Dark", screensaver_idle_time=60,
                   screensaver_ask_password=1, screensaver_password_delay=0,
                   hot_corner_top_left=13)

# Wrong hot corner (Mission Control=2 instead of Lock Screen=13) — no full credits elsewhere.
WRONG_CORNER_ONLY = res(hot_corner_top_left=2)

# Dark + partial timeout (240s) = 20+10 = 30 — fails. No gate because Dark is full credit.
DARK_PLUS_PARTIAL_TIMEOUT = res(appearance="Dark", screensaver_idle_time=240)

# Password required (C3 full) but grace period wrong (3s, not 0, so C4 other).
# Gate does NOT fire because C3 has full credit. Score = 20 (C3 only).
PASSWORD_WRONG_DELAY = res(screensaver_ask_password=1, screensaver_password_delay=3)


if __name__ == "__main__":
    print("=== Offline verifier tests: travel_privacy_lockdown ===")
    results = [
        run("do-nothing",                                     DO_NOTHING,              expect_score=0,  expect_passed=False),
        run("partial timeout only — gate fires",              PARTIAL_TIMEOUT_ONLY,    expect_score=0,  expect_passed=False),
        run("wrong hot corner only — gate fires",             WRONG_CORNER_ONLY,       expect_score=0,  expect_passed=False),
        run("password correct + wrong delay (20, no gate)",     PASSWORD_WRONG_DELAY,    expect_score=20, expect_passed=False),
        run("3/5 correct (threshold edge, 60)",               THREE_OF_FIVE,           expect_score=60, expect_passed=True),
        run("4/5 correct (80)",                               FOUR_OF_FIVE,            expect_score=80, expect_passed=True),
        run("all 5 correct (100)",                            FULL_CORRECT,            expect_score=100,expect_passed=True),
        run("Dark + partial timeout (30, no gate)",           DARK_PLUS_PARTIAL_TIMEOUT, expect_score=30, expect_passed=False),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
