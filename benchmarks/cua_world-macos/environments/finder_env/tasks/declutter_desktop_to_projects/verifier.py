"""Verifier for finder_env's declutter_desktop_to_projects task.

Scoring (100 points, pass at 75):
- 40 pts  C1 (files_correct)   proportional: each file in correct Projects/ subfolder.
- 25 pts  C2 (files_locked)    proportional: each moved file has UF_IMMUTABLE set.
- 20 pts  C3 (readme)          README.txt in each project folder listing ≥3 filenames.
- 15 pts  C4 (desktop_clean)   Desktop has zero HV_/SC_/GD_ files remaining.
"""
from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict

logger = logging.getLogger(__name__)

EXPECTED_FILES: dict[str, set] = {
    "Home Renovation": {
        "HV_kitchen_quotes.txt", "HV_bathroom_tiles.txt", "HV_paint_colors.txt",
        "HV_permit_checklist.txt", "HV_before_photos.txt", "HV_timeline.txt",
    },
    "School Schedule": {
        "SC_fall_schedule.txt", "SC_teacher_contacts.txt", "SC_activities.txt",
        "SC_homework_tracker.txt", "SC_supply_list.txt", "SC_holidays.txt",
    },
    "Garden Design": {
        "GD_zone_map.txt", "GD_bed_layout.txt", "GD_seed_wishlist.txt",
        "GD_irrigation.txt", "GD_composting.txt", "GD_pest_log.txt",
    },
}

ALL_FILES: set = {f for files in EXPECTED_FILES.values() for f in files}
FOLDERS = list(EXPECTED_FILES.keys())
REMOTE_RESULT = "/tmp/declutter_desktop_to_projects_result.json"


def verify_declutter_desktop_to_projects(
    traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]
) -> Dict[str, Any]:
    del traj, task_info

    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"score": 0, "passed": False, "feedback": "env_info missing copy_from_env"}

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        local_path = f.name
    try:
        try:
            copy_from_env(REMOTE_RESULT, local_path)
        except Exception as exc:
            return {"score": 0, "passed": False,
                    "feedback": f"Could not retrieve result file: {exc}"}
        with open(local_path, encoding="utf-8") as fh:
            data: dict = json.load(fh)
    finally:
        try:
            os.unlink(local_path)
        except Exception:
            pass

    score = 0
    details: list[str] = []

    files_by_folder: dict[str, list] = data.get("files_by_folder", {})
    locked_by_file: dict[str, bool] = data.get("locked_by_file", {})
    readme_by_folder: dict[str, Any] = data.get("readme_by_folder", {})
    desktop_leftover: list = data.get("desktop_leftover", [])

    # C1: Files in correct project subfolder (40 pts proportional)
    c1_correct = 0
    for folder, expected in EXPECTED_FILES.items():
        actual = set(files_by_folder.get(folder, []))
        for fn in expected:
            if fn in actual:
                c1_correct += 1
            else:
                details.append(f"'{fn}' not in '{folder}/'")
    c1 = round(c1_correct * 40 / 18)
    score += c1

    # C2: Files locked (25 pts proportional)
    c2_locked = sum(1 for v in locked_by_file.values() if v)
    c2_total = len(locked_by_file)
    c2 = round(c2_locked * 25 / max(c2_total, 18)) if c2_total else 0
    if c2_locked < c2_total:
        details.append(f"Only {c2_locked}/{c2_total} files are locked")
    score += c2

    # C3: README.txt with ≥3 filenames per folder (20 pts — 7+7+6)
    readme_pts = [7, 7, 6]
    c3 = 0
    for i, folder in enumerate(FOLDERS):
        readme = readme_by_folder.get(folder)
        if readme is None:
            details.append(f"No README.txt in '{folder}/'")
            continue
        mentioned = sum(1 for fn in EXPECTED_FILES[folder] if fn in readme)
        if mentioned >= 3:
            c3 += readme_pts[i]
        elif mentioned > 0:
            c3 += round(readme_pts[i] * mentioned / 6)
            details.append(f"README in '{folder}' mentions {mentioned}/6 filenames")
        else:
            details.append(f"README in '{folder}' mentions no expected filenames")
    score += c3

    # C4: Desktop clear (15 pts)
    c4 = 0
    if not desktop_leftover:
        c4 = 15
    else:
        details.append(f"Desktop still has {len(desktop_leftover)} project file(s): {desktop_leftover[:3]}")
    score += c4

    passed = score >= 75
    feedback = f"Score: {score}/100. " + ("; ".join(details) if details else "All criteria met.")
    return {"passed": passed, "score": score, "feedback": feedback}
