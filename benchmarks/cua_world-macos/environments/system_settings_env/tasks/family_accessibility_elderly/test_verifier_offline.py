"""Offline mock tests for verify_family_accessibility_elderly.

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/system_settings_env/tasks/family_accessibility_elderly/test_verifier_offline.py
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
verify = mod.verify_family_accessibility_elderly


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


def res(*, increase_contrast=False, reduce_transparency=False, cursor_size=1.0,
        scroll_wheel_zoom=False, sticky_key=False, slow_key=False) -> dict:
    return {
        "task_start": TASK_START,
        "increase_contrast": increase_contrast,
        "reduce_transparency": reduce_transparency,
        "cursor_size": cursor_size,
        "scroll_wheel_zoom": scroll_wheel_zoom,
        "sticky_key": sticky_key,
        "slow_key": slow_key,
        "read_errors": [],
    }


# All baseline.
DO_NOTHING = res()

# Cursor partially enlarged (1.5 < 3.0) — only change, no full-credit criterion.
CURSOR_PARTIAL_ONLY = res(cursor_size=2.0)

# 3 of 6 correct (contrast + transparency + cursor ≥ 3.0) = 20+20+20 = 60.
THREE_OF_SIX = res(increase_contrast=True, reduce_transparency=True, cursor_size=3.5)

# 4 of 6 correct = 20+20+20+15 = 75.
FOUR_OF_SIX = res(increase_contrast=True, reduce_transparency=True, cursor_size=3.5, scroll_wheel_zoom=True)

# All 6 correct = 100.
FULL_CORRECT = res(increase_contrast=True, reduce_transparency=True, cursor_size=3.5,
                   scroll_wheel_zoom=True, sticky_key=True, slow_key=True)

# 2 of 6 correct (contrast + slow_key) = 20+10 = 30 — below threshold.
PARTIAL_2_OF_6 = res(increase_contrast=True, slow_key=True)

# Cursor at medium (2.0) + one full-credit criterion → strict gate does NOT fire.
# contrast=True (20) + cursor=2.0 (10 partial) = 30 — fails but no strict gate.
CONTRAST_PLUS_MEDIUM_CURSOR = res(increase_contrast=True, cursor_size=2.0)

# Cursor partial only — strict gate fires (no full-credit, only partial cursor).
STRICT_GATE_PARTIAL_CURSOR = res(cursor_size=2.0)


if __name__ == "__main__":
    print("=== Offline verifier tests: family_accessibility_elderly ===")
    results = [
        run("do-nothing",                               DO_NOTHING,              expect_score=0,  expect_passed=False),
        run("cursor partial only — strict gate fires",  CURSOR_PARTIAL_ONLY,     expect_score=0,  expect_passed=False),
        run("strict gate fires (partial cursor only)",  STRICT_GATE_PARTIAL_CURSOR, expect_score=0, expect_passed=False),
        run("3/6 correct (threshold edge, 60)",         THREE_OF_SIX,            expect_score=60, expect_passed=True),
        run("4/6 correct (75)",                         FOUR_OF_SIX,             expect_score=75, expect_passed=True),
        run("all 6 correct (100)",                      FULL_CORRECT,            expect_score=100,expect_passed=True),
        run("2/6 correct (30, below threshold)",        PARTIAL_2_OF_6,          expect_score=30, expect_passed=False),
        run("1 full + medium cursor partial (30)",      CONTRAST_PLUS_MEDIUM_CURSOR, expect_score=30, expect_passed=False),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
