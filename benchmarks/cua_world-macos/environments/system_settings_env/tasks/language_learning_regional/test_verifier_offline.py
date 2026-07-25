"""Offline mock tests for verify_language_learning_regional.

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/system_settings_env/tasks/language_learning_regional/test_verifier_offline.py
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
verify = mod.verify_language_learning_regional


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


def res(*, has_french_language=False, measurement_units="Inches",
        temperature_unit="Fahrenheit", clock_is_24h=False,
        clock_date_format="EEE MMM d  h:mm a",
        first_weekday_gregorian=1) -> dict:
    return {
        "task_start": TASK_START,
        "has_french_language": has_french_language,
        "measurement_units": measurement_units,
        "temperature_unit": temperature_unit,
        "clock_is_24h": clock_is_24h,
        "clock_date_format": clock_date_format,
        "first_weekday_gregorian": first_weekday_gregorian,
        "read_errors": [],
    }


DO_NOTHING = res()

# Only Millimeters (not Centimeters, not Inches) set — c2_other=True, no full → gate 2 fires.
WRONG_UNITS_ONLY = res(measurement_units="Millimeters")

# Only Saturday (gregorian=7, not 2 Monday, not 1 Sunday) set — c5_other=True, no full → gate 2.
WRONG_WEEKDAY_ONLY = res(first_weekday_gregorian=7)

# Metric + Celsius correct but no French/clock/weekday = 40. No gate (has full credits).
METRIC_CELSIUS_ONLY = res(measurement_units="Centimeters", temperature_unit="Celsius")

# 3 of 5 correct: French + metric + Celsius = 60. Threshold edge.
THREE_OF_FIVE = res(has_french_language=True, measurement_units="Centimeters", temperature_unit="Celsius")

# 4 of 5 correct: + 24h clock = 80.
FOUR_OF_FIVE = res(has_french_language=True, measurement_units="Centimeters",
                   temperature_unit="Celsius", clock_is_24h=True,
                   clock_date_format="EEE MMM d  HH:mm")

# All 5 correct = 100.
FULL_CORRECT = res(has_french_language=True, measurement_units="Centimeters",
                   temperature_unit="Celsius", clock_is_24h=True,
                   clock_date_format="EEE MMM d  HH:mm",
                   first_weekday_gregorian=2)

# Monday only correct (20) — no other_flags, so no gate; passes 20 pts.
MONDAY_ONLY = res(first_weekday_gregorian=2)

# French + 24h only = 40 — fails.
FRENCH_24H_ONLY = res(has_french_language=True, clock_is_24h=True,
                      clock_date_format="EEE MMM d  HH:mm")


if __name__ == "__main__":
    print("=== Offline verifier tests: language_learning_regional ===")
    results = [
        run("do-nothing",                                   DO_NOTHING,          expect_score=0,   expect_passed=False),
        run("wrong units only — gate 2 fires",              WRONG_UNITS_ONLY,    expect_score=0,   expect_passed=False),
        run("wrong weekday only — gate 2 fires",            WRONG_WEEKDAY_ONLY,  expect_score=0,   expect_passed=False),
        run("metric+Celsius only (2/5, 40, fails)",         METRIC_CELSIUS_ONLY, expect_score=40,  expect_passed=False),
        run("3/5 correct (threshold edge, 60)",             THREE_OF_FIVE,       expect_score=60,  expect_passed=True),
        run("4/5 correct (80)",                             FOUR_OF_FIVE,        expect_score=80,  expect_passed=True),
        run("all 5 correct (100)",                          FULL_CORRECT,        expect_score=100, expect_passed=True),
        run("Monday only (20, fails, no gate)",             MONDAY_ONLY,         expect_score=20,  expect_passed=False),
        run("French + 24h only (40, fails)",                FRENCH_24H_ONLY,     expect_score=40,  expect_passed=False),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
