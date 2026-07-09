"""Offline mock tests for verify_presentation_mode_setup.

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/system_settings_env/tasks/presentation_mode_setup/test_verifier_offline.py

Per task_creation_notes/13_file_content_verification_and_offline_testing.md:
required scenarios are do-nothing, wrong-target, partial, and full-correct.

Each scenario injects a fabricated result dict (the shape produced by
export_result.sh) and asserts the verifier's score and pass decision.
Exits non-zero on any assertion failure so CI can gate on it.
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
verify = mod.verify_presentation_mode_setup


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


def res(*, appearance=None, dock_orientation="bottom", dock_autohide=False,
        dock_tilesize=48, clock_date_format="EEE MMM d  h:mm a",
        clock_show_ampm=True) -> dict:
    """Build a result dict shaped like export_result.sh's output. Default
    arguments give the baseline (do-nothing) state.

    Live-test finding (2026-05): the System Settings UI's "Show AM/PM" toggle
    writes ShowAMPM=false without updating DateFormat. So `clock_is_24h` is
    derived from EITHER signal — DateFormat contains "HH" (Terminal path) OR
    ShowAMPM=False (UI path).
    """
    if clock_date_format is None:
        df_is_24h = False
    else:
        fmt = clock_date_format
        df_is_24h = ("HH" in fmt) and (" a" not in fmt and not fmt.endswith("a") and "aa" not in fmt)
    clock_is_24h = df_is_24h or (clock_show_ampm is False)
    return {
        "task_start": TASK_START,
        "appearance": appearance,
        "dock_orientation": dock_orientation,
        "dock_autohide": dock_autohide,
        "dock_tilesize": dock_tilesize,
        "clock_date_format": clock_date_format,
        "clock_show_ampm": clock_show_ampm,
        "clock_is_24h": clock_is_24h,
        "any_settings_touched": any([
            appearance is not None,
            dock_orientation != "bottom" and dock_orientation is not None,
            dock_autohide is True,
            dock_tilesize is not None and dock_tilesize != 48,
            clock_date_format is not None and clock_date_format != "EEE MMM d  h:mm a",
            clock_show_ampm is False,
        ]),
        "read_errors": [],
    }


# All baseline values — no agent action.
DO_NOTHING = res()

# Strict wrong-target: agent toggled Dock orientation to "right" and Dock size to 64
# but nothing matched the task target. No criterion full-credits → gate fires.
WRONG_TARGET = res(dock_orientation="right", dock_tilesize=64)

# Partial: 2 of 5 correct (Dark + autohide). Score 40 — below threshold.
PARTIAL_2_OF_5 = res(appearance="Dark", dock_autohide=True)

# Threshold edge: 3 of 5 correct = 60 (passes exactly at threshold).
THREE_OF_FIVE = res(appearance="Dark", dock_autohide=True, dock_orientation="left")

# Four of five correct = 80.
FOUR_OF_FIVE = res(
    appearance="Dark", dock_orientation="left", dock_autohide=True,
    dock_tilesize=16,
    # clock untouched — still 12-hour
)

# Full correct = 100.
FULL_CORRECT = res(
    appearance="Dark",
    dock_orientation="left",
    dock_autohide=True,
    dock_tilesize=16,
    clock_date_format="EEE MMM d  HH:mm",
)

# Tilesize partial: agent changed dock size but not small enough.
# 1 (autohide=true) full-credit + 10 partial tilesize = 30 → fail.
TILESIZE_PARTIAL = res(dock_autohide=True, dock_tilesize=40)

# Mass-mistake all wrong target values + nothing at task target → strict gate.
# Dock right (5 pts partial), tilesize 64 (10 pts partial). Without strict
# gate, that's 15 — but strict gate fires because any_other AND no_full.
MASS_MISTAKE_NO_TARGET = res(dock_orientation="right", dock_tilesize=64)

# Mass-mistake but one criterion correct: strict gate does NOT fire because
# any(full_flags) is True. Score should be the sum of all earned credits.
# Dark mode full (20) + dock right (5 partial) + tilesize 64 (10 partial) = 35.
MIXED_HAS_ONE_FULL = res(
    appearance="Dark", dock_orientation="right", dock_tilesize=64,
)

# UI-path 24h: agent toggled "Show AM/PM" off in Clock Options (System Settings
# UI path observed live on the use.computer fleet). ShowAMPM=False, DateFormat
# unchanged. The verifier should still award full credit for C5 because the
# UI path is legitimate and the menu bar renders 24-hour. With the other
# 4 settings at their target values, total should be 100.
FULL_VIA_UI_TOGGLE = res(
    appearance="Dark",
    dock_orientation="left",
    dock_autohide=True,
    dock_tilesize=16,
    clock_date_format="EEE MMM d  h:mm a",   # unchanged by the UI toggle
    clock_show_ampm=False,                    # toggled off in UI
)

# Mixed: ShowAMPM=False (24h via UI) is the ONLY setting changed — should
# score 20 only on C5, then strict gate may fire because others are baseline.
# Actually with one full credit, gate does NOT fire — score should be 20.
ONLY_C5_VIA_UI = res(clock_show_ampm=False)


if __name__ == "__main__":
    print("=== Offline verifier tests: presentation_mode_setup ===")
    results = [
        run("do-nothing",                          DO_NOTHING,             expect_score=0,   expect_passed=False),
        run("strict wrong-target gate fires",      WRONG_TARGET,           expect_score=0,   expect_passed=False),
        run("partial 2/5 correct (Dark+autohide)", PARTIAL_2_OF_5,         expect_score=40,  expect_passed=False),
        run("threshold edge: 3/5 correct",         THREE_OF_FIVE,          expect_score=60,  expect_passed=True),
        run("4/5 correct",                         FOUR_OF_FIVE,           expect_score=80,  expect_passed=True),
        run("full correct (all 5)",                FULL_CORRECT,           expect_score=100, expect_passed=True),
        run("tilesize partial alone fails",        TILESIZE_PARTIAL,       expect_score=30,  expect_passed=False),
        run("mass-mistake gate (Dock right + big)",MASS_MISTAKE_NO_TARGET, expect_score=0,   expect_passed=False),
        run("mixed: 1 full + 2 partial-wrong",     MIXED_HAS_ONE_FULL,     expect_score=35,  expect_passed=False),
        run("full via UI: ShowAMPM=False for C5",  FULL_VIA_UI_TOGGLE,     expect_score=100, expect_passed=True),
        run("only C5 via UI toggle",               ONLY_C5_VIA_UI,         expect_score=20,  expect_passed=False),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
