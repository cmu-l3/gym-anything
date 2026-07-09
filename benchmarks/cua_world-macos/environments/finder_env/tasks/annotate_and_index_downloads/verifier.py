"""Verifier for finder_env's annotate_and_index_downloads task.

Scoring (100 points, pass at 70):
- 30 pts  C1 (files_correct)   2 pts per file × 15 files in correct Organized/ subfolder.
- 20 pts  C2 (color_tags)      proportional: correct color tag (Blue/Yellow/Green/Red/Gray).
- 25 pts  C3 (comments)        proportional: Finder comment ≥5 words per file.
- 25 pts  C4 (index_file)      ~/Desktop/File_Index.txt: exists (5) + 15 pipe-sep lines (10)
                                 + all 15 filenames referenced (10).
"""
from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict

logger = logging.getLogger(__name__)

EXPECTED: dict[str, tuple[str, str]] = {
    "2024_Tax_Return_Summary.pdf": ("Financial", "Blue"),
    "Bank_Statement_March_2025.pdf": ("Financial", "Blue"),
    "Investment_Portfolio_Q1.pdf": ("Financial", "Blue"),
    "family_reunion_photo.jpg": ("Photos", "Yellow"),
    "kitchen_before.jpg": ("Photos", "Yellow"),
    "garden_sketch.png": ("Photos", "Yellow"),
    "grocery_list.txt": ("Notes", "Green"),
    "book_recs.txt": ("Notes", "Green"),
    "home_repairs.txt": ("Notes", "Green"),
    "workout_playlist.m3u": ("Media", "Red"),
    "relaxing_evenings.m3u": ("Media", "Red"),
    "road_trip_mix.m3u": ("Media", "Red"),
    "hiking_trail_loop.gpx": ("Other", "Gray"),
    "household_budget.xlsx": ("Other", "Gray"),
    "dentist_appointment.ics": ("Other", "Gray"),
}

ALL_FILES = set(EXPECTED.keys())
REMOTE_RESULT = "/tmp/annotate_and_index_downloads_result.json"


def verify_annotate_and_index_downloads(
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
    tags_by_file: dict[str, list] = data.get("tags_by_file", {})
    comments_by_file: dict[str, str] = data.get("comments_by_file", {})

    # C1: Files in correct subfolder (30 pts — 2 each)
    c1 = 0
    for filename, (expected_folder, _) in EXPECTED.items():
        if filename in set(files_by_folder.get(expected_folder, [])):
            c1 += 2
        else:
            details.append(f"'{filename}' not found in {expected_folder}/")
    score += c1

    # C2: Color tags (20 pts proportional)
    c2_count = 0
    for filename, (_, expected_tag) in EXPECTED.items():
        if expected_tag in tags_by_file.get(filename, []):
            c2_count += 1
        else:
            details.append(f"'{filename}': expected {expected_tag} tag, got {tags_by_file.get(filename, [])}")
    c2 = round(c2_count * 20 / 15)
    score += c2

    # C3: Comments ≥5 words (25 pts proportional)
    c3_count = 0
    for filename in EXPECTED:
        comment = comments_by_file.get(filename, "")
        if len([w for w in comment.split() if w]) >= 5:
            c3_count += 1
        else:
            details.append(f"'{filename}': comment <5 words ('{comment}')")
    c3 = round(c3_count * 25 / 15)
    score += c3

    # C4: File_Index.txt (25 pts)
    c4 = 0
    if data.get("index_exists"):
        c4 += 5
        lines = data.get("index_lines", [])
        pipe_lines = [ln for ln in lines if "|" in ln]
        if len(pipe_lines) >= 15:
            c4 += 10
        elif pipe_lines:
            c4 += round(10 * len(pipe_lines) / 15)
            details.append(f"Index has {len(pipe_lines)} formatted lines (need 15)")
        index_text = "\n".join(lines)
        referenced = sum(1 for fn in ALL_FILES if fn in index_text)
        if referenced >= 15:
            c4 += 10
        elif referenced > 0:
            c4 += round(10 * referenced / 15)
            details.append(f"Index references {referenced}/15 filenames")
        else:
            details.append("Index does not reference any expected filenames")
    else:
        details.append("~/Desktop/File_Index.txt not found")
    score += c4

    passed = score >= 70
    feedback = f"Score: {score}/100. " + ("; ".join(details) if details else "All criteria met.")
    return {"passed": passed, "score": score, "feedback": feedback}
