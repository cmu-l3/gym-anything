"""Verifier for finder_env's organize_downloads_by_type task.

Scoring (100 points, pass at 80):
- 24 pts  C1 (folders_exist)     6 pts × 4 folders. Binary per folder.
- 64 pts  C2 (files_correct)     8 pts × 8 files. A file scores iff present
                                 at ~/Downloads/<expected_folder>/<filename>.
                                 Misplaced or missing files score 0.
- 12 pts  C3 (root_clean)        Full credit if 0 loose files at root;
                                 6 pts partial if 1–2 loose; 0 if ≥3.

Strategy enumeration table (Anti-Pattern #13 in 14_task_design_antipatterns.md):

| Strategy                                  | C1 | C2 | C3 | Total | Pass? |
|-------------------------------------------|----|----|----|-------|-------|
| Do-nothing (8 files at root, no folders)  |  0 |  0 |  0 |     0 |  No   |
| Create 4 folders only, no moves           | 24 |  0 |  0 |    24 |  No   |
| Mass-dump all 8 → Documents/              | 24 | 16 | 12 |    52 |  No   |
| Mass-dump all 8 → one wrong folder        |  6 |  0 | 12 |    18 |  No   |
| Move 4/8 correctly, leave 4 at root       | 24 | 32 |  0 |    56 |  No   |
| Move 5/8 correctly, leave 0 at root *     | 24 | 40 | 12 |    76 |  No   |
| Move 6/8 correctly, leave 0 at root *     | 24 | 48 | 12 |    84 |  Yes  |
| Move 7/8 correctly, leave 1 at root *     | 24 | 56 |  6 |    86 |  Yes  |
| Wrong-folder names ("PDFs", etc.) only    |  0 |  0 | 12 |    12 |  No   |
| Delete everything                         |  0 |  0 | 12 |    12 |  No   |
| Correct (all 8 in right folders)          | 24 | 64 | 12 |   100 |  Yes  |

* N/8 means 8-N files are missing entirely OR misplaced (the verifier
  zeros their per-file credit either way). To achieve root_clean=12 the
  agent must have removed/relocated those files from the root, just not
  into a correct folder.

Pass threshold 80 means at least 6/8 correctly placed AND root clean (or
7/8 + 1 loose). Bumped from 70 in audit B2 (2026-05-18) — 5/8 was felt
too permissive for a task whose description says "move every file".

Strict wrong-target gate (Pattern #2 in 03_verification_patterns.md):
  If extra_folders is non-empty AND none of the 4 expected folders exist
  AND no expected file is in any correct location → score=0. This is the
  "agent invented 'Misc/', 'Files/', etc." case.

Sentinel guard (Anti-Pattern #9): if `sentinel_seed_present` is False
(no seed file is anywhere in the ~/Downloads tree), then the agent
either deleted everything or the filesystem export was incomplete.
Either way, every absence criterion would pass trivially → return
score=0 with feedback explaining.

Read pattern: copy_from_env(/tmp/organize_downloads_by_type_result.json,
local_tmp) — produced by export_result.sh.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict


logger = logging.getLogger(__name__)

EXPECTED_FOLDERS = ["Documents", "Images", "Archives", "Other"]
EXPECTED_PLACEMENT = {
    "Documents": ["reading_list.pdf", "meeting_notes.txt"],
    "Images":    ["wallpaper.jpg", "screenshot.png"],
    "Archives":  ["backup.zip", "data.tar.gz"],
    "Other":     ["playlist.m3u", "route_planning.gpx"],
}
ALL_SEED_NAMES = [n for files in EXPECTED_PLACEMENT.values() for n in files]
PASS_THRESHOLD = 80
REMOTE_RESULT = "/tmp/organize_downloads_by_type_result.json"


def _empty_subscores() -> Dict[str, int]:
    return {"folders_exist": 0, "files_correct": 0, "root_clean": 0}


def verify_organize_downloads_by_type(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    del traj, task_info
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"score": 0, "passed": False, "feedback": "env_info missing copy_from_env",
                "subscores": _empty_subscores()}

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        local_path = f.name
    try:
        try:
            copy_from_env(REMOTE_RESULT, local_path)
        except Exception as exc:
            logger.warning("copy_from_env failed: %s", exc)
            return {"score": 0, "passed": False,
                    "feedback": f"Could not retrieve result file from sandbox: {exc}",
                    "subscores": _empty_subscores()}
        try:
            with open(local_path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except Exception as exc:
            logger.warning("result JSON parse failed: %s", exc)
            return {"score": 0, "passed": False,
                    "feedback": f"Export produced unparseable JSON: {exc}",
                    "subscores": _empty_subscores()}
    finally:
        try:
            os.unlink(local_path)
        except Exception:
            pass

    subscores = _empty_subscores()
    feedback: list[str] = []

    subfolder_exists = data.get("subfolder_exists", {}) or {}
    if not isinstance(subfolder_exists, dict):
        subfolder_exists = {}
    expected_correct = data.get("expected_in_correct_folder", {}) or {}
    if not isinstance(expected_correct, dict):
        expected_correct = {}
    root_loose = data.get("root_loose_files", []) or []
    if not isinstance(root_loose, list):
        root_loose = []
    extra_folders = data.get("extra_folders", []) or []
    if not isinstance(extra_folders, list):
        extra_folders = []
    sentinel_present = bool(data.get("sentinel_seed_present", False))

    # ---- Sentinel guard (Anti-Pattern #9) ----
    # If no seed file is anywhere in the tree, either the agent deleted them
    # all or the export was incomplete. Score 0 — absence criteria would
    # otherwise pass trivially (e.g., "root has 0 loose files because there
    # are no files at all"), inflating the do-effectively-nothing score.
    if not sentinel_present:
        return {"score": 0, "passed": False,
                "feedback": "Sentinel failed: none of the 8 seeded files were found anywhere "
                            "under ~/Downloads/. Either the agent deleted them or the export "
                            "could not read the directory. Scoring suppressed to avoid "
                            "rewarding empty-state absence.",
                "subscores": _empty_subscores()}

    # ---- Strict wrong-target gate (Pattern #2) ----
    # Agent created folders with non-matching names (Misc/, PDFs/, …),
    # didn't create any of the 4 expected folders, and didn't place any
    # expected file in its correct location. Score 0, regardless of any
    # accidental credit C3 might have awarded.
    any_expected_folder = any(subfolder_exists.get(f, False) for f in EXPECTED_FOLDERS)
    any_correct_placement = any(expected_correct.get(n, False) for n in ALL_SEED_NAMES)
    if extra_folders and not any_expected_folder and not any_correct_placement:
        return {"score": 0, "passed": False,
                "feedback": (f"Wrong target: created folders {extra_folders} but none of the "
                             f"required folders {EXPECTED_FOLDERS}, and no expected file is in "
                             f"a correct location."),
                "subscores": _empty_subscores()}

    # ---- C1: subfolders exist (24 pts; 6 each, binary) ----
    folders_present, folders_missing = [], []
    for f in EXPECTED_FOLDERS:
        if subfolder_exists.get(f, False):
            subscores["folders_exist"] += 6
            folders_present.append(f)
        else:
            folders_missing.append(f)
    if subscores["folders_exist"] == 24:
        feedback.append(f"All 4 category folders created (+24)")
    elif subscores["folders_exist"] > 0:
        feedback.append(
            f"Created {len(folders_present)}/4 folders: {', '.join(folders_present)} "
            f"(+{subscores['folders_exist']}). Missing: {', '.join(folders_missing)}"
        )
    else:
        feedback.append("None of the 4 category folders were created (+0)")

    # ---- C2: each expected file is in its correct folder (64 pts; 8 each) ----
    correct, missing = [], []
    for name in ALL_SEED_NAMES:
        if expected_correct.get(name, False):
            subscores["files_correct"] += 8
            correct.append(name)
        else:
            missing.append(name)
    if subscores["files_correct"] == 64:
        feedback.append("All 8 files placed in their correct folder (+64)")
    elif subscores["files_correct"] > 0:
        feedback.append(
            f"{len(correct)}/8 files correctly placed: {', '.join(correct)} "
            f"(+{subscores['files_correct']}). Missing or misplaced: {', '.join(missing)}"
        )
    else:
        feedback.append("No file is in its correct category folder (+0)")

    # ---- C3: root of ~/Downloads is clean (12 pts) ----
    loose_count = len(root_loose)
    if loose_count == 0:
        subscores["root_clean"] = 12
        feedback.append("Root of ~/Downloads has no loose files (+12)")
    elif loose_count <= 2:
        subscores["root_clean"] = 6
        feedback.append(
            f"Root of ~/Downloads has {loose_count} loose file(s) left: {', '.join(root_loose)} (+6)"
        )
    else:
        feedback.append(
            f"Root of ~/Downloads still has {loose_count} loose files: {', '.join(root_loose)} (+0)"
        )

    if extra_folders:
        feedback.append(f"Note: also created non-required folders: {', '.join(extra_folders)} "
                        f"(no penalty, but counts as clutter).")

    total = sum(subscores.values())
    passed = total >= PASS_THRESHOLD
    if passed:
        feedback.insert(0, f"PASSED ({total}/100): Downloads organized successfully.")
    else:
        feedback.insert(0, f"FAILED ({total}/100): organization incomplete (pass threshold {PASS_THRESHOLD}).")
    return {"score": total, "passed": passed, "feedback": " | ".join(feedback), "subscores": subscores}
