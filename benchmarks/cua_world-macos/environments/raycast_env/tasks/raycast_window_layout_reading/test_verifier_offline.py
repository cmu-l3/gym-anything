"""Offline unit tests for verify_window_layout_reading."""

import importlib.util
import json
import os

_spec = importlib.util.spec_from_file_location(
    "verifier",
    os.path.join(os.path.dirname(__file__), "verifier.py"),
)
mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mod)


def _make_env(result_data):
    def copy_from_env(src, dst):
        with open(dst, "w") as f:
            json.dump(result_data, f)
    return {"copy_from_env": copy_from_env}


def _make_env_missing():
    def copy_from_env(src, dst):
        raise FileNotFoundError(src)
    return {"copy_from_env": copy_from_env}


SCREEN = [0, 0, 1920, 1080]
# Safari occupying left half (x=0, w=960 -> right edge at 960 -> 50%)
SAFARI_LEFT  = [0, 25, 960, 1055]
# Notes occupying right half (x=960, w=960 -> right edge at 1920 -> 100%)
NOTES_RIGHT  = [960, 25, 960, 1055]
# Off-target positions
SAFARI_RIGHT = [960, 25, 960, 1055]
NOTES_LEFT   = [0, 25, 960, 1055]


def _result(**overrides):
    base = {
        "task_start": 1748300000,
        "screen_bounds": SCREEN,
        "safari_running": True,
        "notes_running": True,
        "safari_url": "https://news.ycombinator.com/",
        "safari_frame": SAFARI_LEFT,
        "notes_frame": NOTES_RIGHT,
    }
    base.update(overrides)
    return base


def test_missing_result_file():
    r = mod.verify_window_layout_reading([], _make_env_missing(), {})
    assert r["passed"] is False and r["score"] == 0
    print("PASS test_missing_result_file")


def test_nothing_running():
    r = mod.verify_window_layout_reading([], _make_env(_result(
        safari_running=False, notes_running=False, safari_url="",
        safari_frame=None, notes_frame=None
    )), {})
    assert r["passed"] is False
    assert r["score"] == 0
    print(f"PASS test_nothing_running (score={r['score']})")


def test_only_safari_running_with_url():
    r = mod.verify_window_layout_reading([], _make_env(_result(
        notes_running=False, notes_frame=None
    )), {})
    # C1=15, C2=0, C3=25, C4=25, C5=0 -> 65
    assert r["score"] == 65, f"Expected 65, got {r['score']}"
    assert r["passed"] is False
    print(f"PASS test_only_safari_running_with_url (score={r['score']})")


def test_wrong_url():
    r = mod.verify_window_layout_reading([], _make_env(_result(
        safari_url="https://www.google.com/"
    )), {})
    # C1=15, C2=15, C3=0, C4=25, C5=20 -> 75
    assert r["score"] == 75, f"Expected 75, got {r['score']}"
    assert r["passed"] is True  # still passes (>= 70)
    print(f"PASS test_wrong_url (score={r['score']})")


def test_swapped_positions():
    """Safari on right, Notes on left — wrong layout."""
    r = mod.verify_window_layout_reading([], _make_env(_result(
        safari_frame=SAFARI_RIGHT, notes_frame=NOTES_LEFT
    )), {})
    # C1=15, C2=15, C3=25, C4=0, C5=0 -> 55
    assert r["score"] == 55, f"Expected 55, got {r['score']}"
    assert r["passed"] is False
    print(f"PASS test_swapped_positions (score={r['score']})")


def test_all_correct():
    r = mod.verify_window_layout_reading([], _make_env(_result()), {})
    assert r["passed"] is True
    assert r["score"] == 100, f"Expected 100, got {r['score']}"
    print(f"PASS test_all_correct (score={r['score']})")


def test_slightly_off_positions_still_pass():
    """Windows are slightly off — 10% offset from perfect — still within tolerance."""
    safari_slight  = [50, 50, 880, 1000]   # right edge 930/1920 = 48% (within 40-65)
    notes_slight   = [990, 50, 880, 1000]  # left edge 990/1920 = 52% (within 35-60), right 1870/1920=97%
    r = mod.verify_window_layout_reading([], _make_env(_result(
        safari_frame=safari_slight, notes_frame=notes_slight
    )), {})
    assert r["passed"] is True
    assert r["score"] == 100, f"Expected 100 (within tolerance), got {r['score']}"
    print(f"PASS test_slightly_off_positions_still_pass (score={r['score']})")


def test_fullscreen_safari_not_left_half():
    """Safari is maximized, covering the whole screen — not left-half."""
    fullscreen = [0, 0, 1920, 1080]
    r = mod.verify_window_layout_reading([], _make_env(_result(
        safari_frame=fullscreen
    )), {})
    # C4 fails because right edge at 100% > 65%
    # Score = 15+15+25+0+20 = 75
    assert r["score"] == 75, f"Expected 75, got {r['score']}"
    print(f"PASS test_fullscreen_safari_not_left_half (score={r['score']})")


if __name__ == "__main__":
    test_missing_result_file()
    test_nothing_running()
    test_only_safari_running_with_url()
    test_wrong_url()
    test_swapped_positions()
    test_all_correct()
    test_slightly_off_positions_still_pass()
    test_fullscreen_safari_not_left_half()
    print("\nAll Task 2 offline tests passed.")
