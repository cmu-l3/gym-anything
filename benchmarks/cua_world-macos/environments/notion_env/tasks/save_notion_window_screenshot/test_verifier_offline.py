"""Offline mock tests for verify_save_notion_window_screenshot.

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/notion_env/tasks/save_notion_window_screenshot/test_verifier_offline.py

Per task_creation_notes/13_file_content_verification_and_offline_testing.md
Gap 2: tests inject the EXACT JSON the export script produces, mocking
`copy_from_env` so the verifier reads the synthetic data. The mock dicts
mirror the field names emitted by export_result.sh's Python heredoc —
see Anti-Pattern 6 (export/verifier field-name mismatch).

Includes the MENU_BAR_CAPTURE scenario the 2026-05-17 audit flagged: a
fresh, valid PNG, real screencapture xattr, type='window' — but
dimensions 1920×24 (just the macOS menu bar strip). The C6 dimension
gate must reject it.
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
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
verify = mod.verify_save_notion_window_screenshot


def make_env_info(fake_result: dict) -> dict:
    fixture = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    fixture.write(json.dumps(fake_result).encode())
    fixture.close()

    def copy_from_env(_remote: str, local: str) -> None:
        shutil.copy(fixture.name, local)

    return {"copy_from_env": copy_from_env, "_fixture": fixture.name}


def run(name: str, fake_result: dict, expect_score, expect_passed: bool) -> bool:
    env_info = make_env_info(fake_result)
    out = verify(traj={}, env_info=env_info, task_info={})
    Path(env_info["_fixture"]).unlink(missing_ok=True)
    score = out["score"]
    passed = out["passed"]
    if isinstance(expect_score, tuple):
        lo, hi = expect_score
        score_ok = lo <= score <= hi
        expect_desc = f"{lo}..{hi}"
    else:
        score_ok = score == expect_score
        expect_desc = str(expect_score)
    pass_ok = passed == expect_passed
    status = "PASS" if (score_ok and pass_ok) else "FAIL"
    print(
        f"[{status}] {name}: got score={score} passed={passed} "
        f"(expected score={expect_desc} passed={expect_passed})"
    )
    if not (score_ok and pass_ok):
        print(f"    subscores: {out['subscores']}")
        print(f"    feedback:  {out['feedback']}")
        return False
    return True


TASK_START = 1_700_000_000


def _candidate(*, path, mtime_delta_sec, size, is_png, is_sc, sc_type, dimensions=None):
    """Build a candidate-inspected dict matching the export script's shape."""
    return {
        "path": path,
        "mtime": TASK_START + mtime_delta_sec,
        "fresh": mtime_delta_sec > 0,
        "size": size,
        "is_png_magic": is_png,
        "dimensions": dimensions if dimensions is not None else ([1432, 972] if is_png else None),
        "is_screencapture": is_sc,
        "screencapture_type": sc_type,
    }


# Note: `notion_running` is still emitted by export_result.sh but the verifier
# no longer reads it. The field is retained in the result JSON for debugging /
# evidence-collection use; tests include it for fidelity to actual export output.

DO_NOTHING = {
    "task_start": TASK_START,
    "exported_at": TASK_START + 60,
    "search_dirs": ["/Users/lume/Desktop", "/Users/lume/Documents"],
    "candidate_count_total": 0,
    "candidates_inspected": [],
    "chosen": None,
    "notion_running": True,
}

EMPTY_FRESH_FILE = {
    # `touch ~/Desktop/foo.png` while Notion is up. No size, no PNG bytes,
    # no xattrs, no dimensions. Only C1 (fresh) fires. 10.
    "task_start": TASK_START,
    "exported_at": TASK_START + 30,
    "search_dirs": ["/Users/lume/Desktop", "/Users/lume/Documents"],
    "candidate_count_total": 1,
    "candidates_inspected": [_candidate(
        path="/Users/lume/Desktop/foo.png",
        mtime_delta_sec=10, size=0, is_png=False, is_sc=False, sc_type=None,
        dimensions=None,
    )],
    "chosen": _candidate(
        path="/Users/lume/Desktop/foo.png",
        mtime_delta_sec=10, size=0, is_png=False, is_sc=False, sc_type=None,
        dimensions=None,
    ),
    "notion_running": True,
}

COPIED_NON_SCREENCAP_PNG = {
    # Agent copied an unrelated PNG (e.g. via `curl https://.../logo.png`).
    # PNG bytes valid, size reasonable, dimensions window-shaped (1280x800),
    # but no kMDItemIsScreenCapture xattr.
    # C1 + C2 + C3 + C6 = 10 + 5 + 5 + 30 = 50. Below threshold.
    # (C4 and C5 zero because not a screencapture.)
    "task_start": TASK_START,
    "exported_at": TASK_START + 30,
    "search_dirs": ["/Users/lume/Desktop", "/Users/lume/Documents"],
    "candidate_count_total": 1,
    "candidates_inspected": [_candidate(
        path="/Users/lume/Documents/logo.png",
        mtime_delta_sec=12, size=120_000, is_png=True, is_sc=False, sc_type=None,
        dimensions=[1280, 800],
    )],
    "chosen": _candidate(
        path="/Users/lume/Documents/logo.png",
        mtime_delta_sec=12, size=120_000, is_png=True, is_sc=False, sc_type=None,
        dimensions=[1280, 800],
    ),
    "notion_running": True,
}

FULL_DISPLAY_CAPTURE = {
    # Agent used `screencapture -x` (full-display). Fresh, valid PNG, right
    # size, screencap xattr=True, dimensions 1920x1080 — but sc_type="display"
    # (not "window").
    # C1 + C2 + C3 + C4 + C6 = 10 + 5 + 5 + 20 + 30 = 70. Below threshold.
    "task_start": TASK_START,
    "exported_at": TASK_START + 60,
    "search_dirs": ["/Users/lume/Desktop", "/Users/lume/Documents"],
    "candidate_count_total": 1,
    "candidates_inspected": [_candidate(
        path="/Users/lume/Desktop/Screenshot 2026-05-17 at 10.00.00.png",
        mtime_delta_sec=20, size=1_300_000, is_png=True, is_sc=True, sc_type="display",
        dimensions=[1920, 1080],
    )],
    "chosen": _candidate(
        path="/Users/lume/Desktop/Screenshot 2026-05-17 at 10.00.00.png",
        mtime_delta_sec=20, size=1_300_000, is_png=True, is_sc=True, sc_type="display",
        dimensions=[1920, 1080],
    ),
    "notion_running": True,
}

MENU_BAR_CAPTURE = {
    # The audit's gaming path: agent runs `screencapture -w` and the click
    # lands such that macOS captures the menu bar window (a Notion-owned
    # window when Notion is frontmost). All the metadata gates pass —
    # fresh, valid PNG, reasonable size, kMDItemIsScreenCapture=True,
    # kMDItemScreenCaptureType='window' — but dimensions 1920x24 give an
    # aspect ratio of 80:1, far beyond the 5:1 ceiling. C6 must fire 0.
    # Total: 10 + 5 + 5 + 20 + 30 + 0 = 70. Below threshold.
    "task_start": TASK_START,
    "exported_at": TASK_START + 60,
    "search_dirs": ["/Users/lume/Desktop", "/Users/lume/Documents"],
    "candidate_count_total": 1,
    "candidates_inspected": [_candidate(
        path="/Users/lume/Desktop/notion_window.png",
        mtime_delta_sec=20, size=57_690, is_png=True, is_sc=True, sc_type="window",
        dimensions=[1920, 24],
    )],
    "chosen": _candidate(
        path="/Users/lume/Desktop/notion_window.png",
        mtime_delta_sec=20, size=57_690, is_png=True, is_sc=True, sc_type="window",
        dimensions=[1920, 24],
    ),
    "notion_running": True,
}

TINY_WINDOW_CAPTURE = {
    # Defensive scenario: a screencap of a tooltip / dock item / small
    # transient overlay. ~150x80 — below 400x300 minimum.
    # 10 + 5 + 5 + 20 + 30 + 0 = 70. Below threshold.
    "task_start": TASK_START,
    "exported_at": TASK_START + 60,
    "search_dirs": ["/Users/lume/Desktop", "/Users/lume/Documents"],
    "candidate_count_total": 1,
    "candidates_inspected": [_candidate(
        path="/Users/lume/Desktop/tooltip.png",
        mtime_delta_sec=20, size=40_000, is_png=True, is_sc=True, sc_type="window",
        dimensions=[150, 80],
    )],
    "chosen": _candidate(
        path="/Users/lume/Desktop/tooltip.png",
        mtime_delta_sec=20, size=40_000, is_png=True, is_sc=True, sc_type="window",
        dimensions=[150, 80],
    ),
    "notion_running": True,
}

WINDOW_CAPTURE_HAPPY_PATH = {
    # Agent did the right thing: `screencapture -lWINDOW_ID file.png` for
    # the Notion main window. Capture dims ~1432x972 (the real Notion login
    # window). All criteria fire. 100.
    "task_start": TASK_START,
    "exported_at": TASK_START + 60,
    "search_dirs": ["/Users/lume/Desktop", "/Users/lume/Documents"],
    "candidate_count_total": 1,
    "candidates_inspected": [_candidate(
        path="/Users/lume/Desktop/Screenshot 2026-05-17 at 10.00.00.png",
        mtime_delta_sec=20, size=350_000, is_png=True, is_sc=True, sc_type="window",
        dimensions=[1432, 972],
    )],
    "chosen": _candidate(
        path="/Users/lume/Desktop/Screenshot 2026-05-17 at 10.00.00.png",
        mtime_delta_sec=20, size=350_000, is_png=True, is_sc=True, sc_type="window",
        dimensions=[1432, 972],
    ),
    "notion_running": True,
}

STALE_WINDOW_CAPTURE = {
    # A pre-existing window screenshot from before pre_task. Should fail
    # the freshness gate. C2 (PNG magic), C3 (size in range) still fire
    # on a valid stale PNG — they're file-property checks. C6 is gated
    # on fresh, so it does NOT fire. 5 + 5 = 10.
    "task_start": TASK_START,
    "exported_at": TASK_START + 60,
    "search_dirs": ["/Users/lume/Desktop", "/Users/lume/Documents"],
    "candidate_count_total": 1,
    "candidates_inspected": [_candidate(
        path="/Users/lume/Desktop/Old Screen Shot.png",
        mtime_delta_sec=-3600, size=300_000, is_png=True, is_sc=True, sc_type="window",
        dimensions=[1432, 972],
    )],
    "chosen": _candidate(
        path="/Users/lume/Desktop/Old Screen Shot.png",
        mtime_delta_sec=-3600, size=300_000, is_png=True, is_sc=True, sc_type="window",
        dimensions=[1432, 972],
    ),
    "notion_running": True,
}

OVERSIZE_WINDOW_CAPTURE = {
    # Window capture but file is huge (e.g. of a 5K external display). C3
    # fails because size > 8 MB. Other criteria all fire including C6
    # (dimensions are window-shaped). 100 - 5 = 95.
    "task_start": TASK_START,
    "exported_at": TASK_START + 60,
    "search_dirs": ["/Users/lume/Desktop", "/Users/lume/Documents"],
    "candidate_count_total": 1,
    "candidates_inspected": [_candidate(
        path="/Users/lume/Desktop/Screenshot 2026-05-17 at 10.00.00.png",
        mtime_delta_sec=20, size=10 * 1024 * 1024, is_png=True, is_sc=True, sc_type="window",
        dimensions=[2560, 1600],
    )],
    "chosen": _candidate(
        path="/Users/lume/Desktop/Screenshot 2026-05-17 at 10.00.00.png",
        mtime_delta_sec=20, size=10 * 1024 * 1024, is_png=True, is_sc=True, sc_type="window",
        dimensions=[2560, 1600],
    ),
    "notion_running": True,
}


if __name__ == "__main__":
    print("=== Offline verifier tests: save_notion_window_screenshot ===")
    results = [
        run("do-nothing (no file at all)",
            DO_NOTHING, expect_score=0, expect_passed=False),
        run("touch (empty fresh file)",
            EMPTY_FRESH_FILE, expect_score=10, expect_passed=False),
        run("copied unrelated PNG (no screencap xattr; dims window-shaped)",
            COPIED_NON_SCREENCAP_PNG, expect_score=50, expect_passed=False),
        run("full-display capture (kMDItemScreenCaptureType='display')",
            FULL_DISPLAY_CAPTURE, expect_score=70, expect_passed=False),
        run("menu-bar capture (1920x24 window-mode — audit's gaming path)",
            MENU_BAR_CAPTURE, expect_score=70, expect_passed=False),
        run("tiny window capture (150x80 tooltip)",
            TINY_WINDOW_CAPTURE, expect_score=70, expect_passed=False),
        run("happy path: window capture of Notion body (1432x972)",
            WINDOW_CAPTURE_HAPPY_PATH, expect_score=100, expect_passed=True),
        run("stale window capture (mtime predates task_start)",
            STALE_WINDOW_CAPTURE, expect_score=10, expect_passed=False),
        run("oversize window capture (>8MB; size C3 fails)",
            OVERSIZE_WINDOW_CAPTURE, expect_score=95, expect_passed=True),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
