"""Offline mock tests for verify_organize_downloads_by_type.

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/finder_env/tasks/organize_downloads_by_type/test_verifier_offline.py

Per task_creation_notes/13_file_content_verification_and_offline_testing.md
the required scenarios are do-nothing, wrong-target, partial, and
full-correct. Plus finder-specific anti-gaming scenarios for mass-dump,
delete-everything (sentinel guard), and missing-folder.

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
verify = mod.verify_organize_downloads_by_type


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

ALL_SEEDS = [
    "reading_list.pdf", "meeting_notes.txt",
    "wallpaper.jpg", "screenshot.png",
    "backup.zip", "data.tar.gz",
    "playlist.m3u", "route_planning.gpx",
]
ALL_FOLDERS = ["Documents", "Images", "Archives", "Other"]


def _base_result(**overrides):
    r = {
        "task_start": TASK_START,
        "root_loose_files": [],
        "subfolder_exists": {f: False for f in ALL_FOLDERS},
        "subfolder_contents": {f: [] for f in ALL_FOLDERS},
        "expected_in_correct_folder": {n: False for n in ALL_SEEDS},
        "extra_folders": [],
        "sentinel_seed_present": True,
    }
    r.update(overrides)
    return r


# ---- Scenarios ---------------------------------------------------------

DO_NOTHING = _base_result(
    # 8 seed files all in root, no folders created.
    root_loose_files=list(ALL_SEEDS),
)

ALL_DELETED = _base_result(
    # Agent deleted everything to "clean up". sentinel_seed_present=False
    # → score 0 regardless of root being clean. Distinct from do-nothing
    # in that root_loose_files is also empty, which would otherwise grant
    # C3 12 pts without the sentinel guard.
    sentinel_seed_present=False,
)

WRONG_TARGET_STRICT = _base_result(
    # Agent created folders with non-matching names and put files in them.
    # No expected folder exists, no expected file is in any correct
    # location → strict gate fires → score 0.
    extra_folders=["PDFs", "Pictures", "Compressed", "Misc"],
)

FOLDERS_ONLY = _base_result(
    # Agent created the 4 folders but moved nothing. Files still at root.
    subfolder_exists={f: True for f in ALL_FOLDERS},
    root_loose_files=list(ALL_SEEDS),
)
# C1=24, C2=0, C3=0 → 24

MASS_DUMP_INTO_DOCUMENTS = _base_result(
    # Agent created 4 folders, put ALL 8 files into Documents/. Only the 2
    # files that genuinely belong in Documents/ score C2 credit. Root is clean.
    subfolder_exists={f: True for f in ALL_FOLDERS},
    subfolder_contents={
        "Documents": list(ALL_SEEDS),
        "Images": [], "Archives": [], "Other": [],
    },
    expected_in_correct_folder={
        "reading_list.pdf": True, "meeting_notes.txt": True,
        # All others: False (in Documents/, not their correct folder)
    } | {n: False for n in ALL_SEEDS if n not in ("reading_list.pdf", "meeting_notes.txt")},
)
# C1=24, C2=16 (2*8), C3=12 → 52

PARTIAL_HALF = _base_result(
    # Agent did 4/8 files correctly, left 4 at root.
    subfolder_exists={f: True for f in ALL_FOLDERS},
    expected_in_correct_folder={
        "reading_list.pdf": True, "meeting_notes.txt": True,
        "wallpaper.jpg": True, "screenshot.png": True,
        "backup.zip": False, "data.tar.gz": False,
        "playlist.m3u": False, "route_planning.gpx": False,
    },
    root_loose_files=["backup.zip", "data.tar.gz", "playlist.m3u", "route_planning.gpx"],
)
# C1=24, C2=32 (4*8), C3=0 (4 loose) → 56, below threshold (70)

PARTIAL_FIVE_OF_EIGHT = _base_result(
    # Agent did 5/8 correctly, removed the others from root somehow.
    # (Maybe deleted them, maybe in wrong folders — sentinel still True
    # because 5 expected files are in their correct location, so we found them.)
    subfolder_exists={f: True for f in ALL_FOLDERS},
    expected_in_correct_folder={
        "reading_list.pdf": True, "meeting_notes.txt": True,
        "wallpaper.jpg": True, "screenshot.png": True,
        "backup.zip": True,
        "data.tar.gz": False, "playlist.m3u": False, "route_planning.gpx": False,
    },
    root_loose_files=[],
)
# C1=24, C2=40 (5*8), C3=12 → 76, fails (< 80 after audit B2 bump)

PARTIAL_SIX_OF_EIGHT = _base_result(
    # Agent did 6/8 correctly + root clean. Just over the new threshold.
    subfolder_exists={f: True for f in ALL_FOLDERS},
    expected_in_correct_folder={
        "reading_list.pdf": True, "meeting_notes.txt": True,
        "wallpaper.jpg": True, "screenshot.png": True,
        "backup.zip": True, "data.tar.gz": True,
        "playlist.m3u": False, "route_planning.gpx": False,
    },
    root_loose_files=[],
)
# C1=24, C2=48 (6*8), C3=12 → 84, passes (>= 80)

FULL_CORRECT = _base_result(
    subfolder_exists={f: True for f in ALL_FOLDERS},
    subfolder_contents={
        "Documents": ["reading_list.pdf", "meeting_notes.txt"],
        "Images":    ["wallpaper.jpg", "screenshot.png"],
        "Archives":  ["backup.zip", "data.tar.gz"],
        "Other":     ["playlist.m3u", "route_planning.gpx"],
    },
    expected_in_correct_folder={n: True for n in ALL_SEEDS},
    root_loose_files=[],
)
# C1=24, C2=64, C3=12 → 100

EXTRA_FOLDERS_BUT_CORRECT = _base_result(
    # Agent did the right thing AND also created a bonus "Misc/" folder.
    # No penalty for extras; full credit.
    subfolder_exists={f: True for f in ALL_FOLDERS},
    subfolder_contents={
        "Documents": ["reading_list.pdf", "meeting_notes.txt"],
        "Images":    ["wallpaper.jpg", "screenshot.png"],
        "Archives":  ["backup.zip", "data.tar.gz"],
        "Other":     ["playlist.m3u", "route_planning.gpx"],
    },
    expected_in_correct_folder={n: True for n in ALL_SEEDS},
    root_loose_files=[],
    extra_folders=["Misc"],
)
# Same as FULL_CORRECT: 100

ONE_LOOSE_FILE = _base_result(
    # 7/8 done correctly, 1 file still at root.
    subfolder_exists={f: True for f in ALL_FOLDERS},
    expected_in_correct_folder={n: (n != "route_planning.gpx") for n in ALL_SEEDS},
    root_loose_files=["route_planning.gpx"],
)
# C1=24, C2=56 (7*8), C3=6 (1 loose, partial) → 86, passes


if __name__ == "__main__":
    print("=== Offline verifier tests: organize_downloads_by_type ===")
    results = [
        run("do-nothing (8 files at root, no folders)",          DO_NOTHING,              expect_score=0,   expect_passed=False),
        run("all-deleted (sentinel guard fires)",                ALL_DELETED,             expect_score=0,   expect_passed=False),
        run("wrong-target (only non-required folders)",          WRONG_TARGET_STRICT,     expect_score=0,   expect_passed=False),
        run("folders-only (4 folders, no moves)",                FOLDERS_ONLY,            expect_score=24,  expect_passed=False),
        run("mass-dump (all 8 → Documents/)",                    MASS_DUMP_INTO_DOCUMENTS,expect_score=52,  expect_passed=False),
        run("partial-half (4/8 correct, 4 at root)",             PARTIAL_HALF,            expect_score=56,  expect_passed=False),
        run("partial-5/8 (5/8 correct, root clean)",             PARTIAL_FIVE_OF_EIGHT,   expect_score=76,  expect_passed=False),
        run("partial-6/8 (6/8 correct, root clean)",             PARTIAL_SIX_OF_EIGHT,    expect_score=84,  expect_passed=True),
        run("one-loose-file (7/8 correct, 1 left at root)",      ONE_LOOSE_FILE,          expect_score=86,  expect_passed=True),
        run("full-correct (all 8 in right folders)",             FULL_CORRECT,            expect_score=100, expect_passed=True),
        run("extra-folders-but-correct (Misc/ alongside)",       EXTRA_FOLDERS_BUT_CORRECT, expect_score=100, expect_passed=True),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
