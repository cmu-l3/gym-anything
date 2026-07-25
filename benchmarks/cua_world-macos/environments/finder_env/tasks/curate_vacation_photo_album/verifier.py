"""Verifier for finder_env's curate_vacation_photo_album task.

Scoring (100 points, pass at 70):
- 15 pts  C1 (folder_exists)      5 pts × 3 trip folders.
- 48 pts  C2 (files_correct)      2 pts per file × 24 files in correct trip folder.
- 21 pts  C3 (folder_tags)        7 pts × 3 folders: Blue=GC, Green=PC, Red=NE.
- 12 pts  C4 (highlights)         4 pts per file × 9 highlight files (3 per trip).
-  4 pts  C5 (comments)           Comment on each trip folder names trip + month/year.
"""
from __future__ import annotations

import json
import logging
import os
import re
import tempfile
from typing import Any, Dict

logger = logging.getLogger(__name__)

GC_FILES = {
    "2019-07-10_IMG_0101.jpg", "2019-07-11_IMG_0128.jpg",
    "2019-07-12_IMG_0143.jpg", "2019-07-14_IMG_0189.jpg",
    "2019-07-16_IMG_0221.jpg", "2019-07-17_IMG_0256.jpg",
    "2019-07-19_IMG_0312.jpg", "2019-07-20_IMG_0389.jpg",
}
PC_FILES = {
    "2021-04-01_IMG_1101.jpg", "2021-04-02_IMG_1119.jpg",
    "2021-04-03_IMG_1142.jpg", "2021-04-05_IMG_1178.jpg",
    "2021-04-06_IMG_1204.jpg", "2021-04-08_IMG_1222.jpg",
    "2021-04-09_IMG_1267.jpg", "2021-04-10_IMG_1311.jpg",
}
NE_FILES = {
    "2023-08-18_IMG_2101.jpg", "2023-08-19_IMG_2118.jpg",
    "2023-08-20_IMG_2134.jpg", "2023-08-22_IMG_2167.jpg",
    "2023-08-23_IMG_2194.jpg", "2023-08-25_IMG_2227.jpg",
    "2023-08-26_IMG_2271.jpg", "2023-08-28_IMG_2316.jpg",
}
GC_HIGHLIGHTS = {"2019-07-17_IMG_0256.jpg", "2019-07-19_IMG_0312.jpg", "2019-07-20_IMG_0389.jpg"}
PC_HIGHLIGHTS = {"2021-04-08_IMG_1222.jpg", "2021-04-09_IMG_1267.jpg", "2021-04-10_IMG_1311.jpg"}
NE_HIGHLIGHTS = {"2023-08-25_IMG_2227.jpg", "2023-08-26_IMG_2271.jpg", "2023-08-28_IMG_2316.jpg"}

REMOTE_RESULT = "/tmp/curate_vacation_photo_album_result.json"


def _tag_matches(tag_str: str, expected_color: str) -> bool:
    tags = {t.strip().lower() for t in tag_str.split(",") if t.strip()}
    return expected_color.lower() in tags


def _comment_keywords(comment: str, *keywords: str) -> bool:
    c = comment.lower()
    return all(kw.lower() in c for kw in keywords)


def verify_curate_vacation_photo_album(
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

    # C1: Trip folders exist (15 pts — 5 each)
    c1 = 0
    for key, label in [("gc_folder_exists", "Grand Canyon 2019"),
                       ("pc_folder_exists", "Pacific Coast 2021"),
                       ("ne_folder_exists", "New England 2023")]:
        if data.get(key):
            c1 += 5
        else:
            details.append(f"Missing folder: {label}")
    score += c1

    # C2: Files in correct trip folder (48 pts — 2 per file)
    c2 = 0
    gc_actual = set(data.get("gc_files", []))
    pc_actual = set(data.get("pc_files", []))
    ne_actual = set(data.get("ne_files", []))
    for f in GC_FILES:
        if f in gc_actual:
            c2 += 2
        else:
            details.append(f"GC missing: {f}")
    for f in PC_FILES:
        if f in pc_actual:
            c2 += 2
        else:
            details.append(f"PC missing: {f}")
    for f in NE_FILES:
        if f in ne_actual:
            c2 += 2
        else:
            details.append(f"NE missing: {f}")
    score += c2

    # C3: Folder color tags (21 pts — 7 each)
    c3 = 0
    if _tag_matches(data.get("gc_tag", ""), "Blue"):
        c3 += 7
    else:
        details.append(f"GC tag wrong (got '{data.get('gc_tag', '')}', expected Blue)")
    if _tag_matches(data.get("pc_tag", ""), "Green"):
        c3 += 7
    else:
        details.append(f"PC tag wrong (got '{data.get('pc_tag', '')}', expected Green)")
    if _tag_matches(data.get("ne_tag", ""), "Red"):
        c3 += 7
    else:
        details.append(f"NE tag wrong (got '{data.get('ne_tag', '')}', expected Red)")
    score += c3

    # C4: Highlights subfolder (12 pts — 4 per complete trip set)
    c4 = 0
    gc_hi = set(data.get("gc_highlights", []))
    pc_hi = set(data.get("pc_highlights", []))
    ne_hi = set(data.get("ne_highlights", []))
    for trip_hi, hi_set, name in [
        (GC_HIGHLIGHTS, gc_hi, "GC"),
        (PC_HIGHLIGHTS, pc_hi, "PC"),
        (NE_HIGHLIGHTS, ne_hi, "NE"),
    ]:
        correct = len(trip_hi & hi_set)
        c4 += round(4 * correct / 3)
        if correct < 3:
            missing = trip_hi - hi_set
            details.append(f"{name} Highlights missing: {', '.join(sorted(missing))}")
    score += c4

    # C5: Comments with trip name + date (4 pts)
    c5 = 0
    if _comment_keywords(data.get("gc_comment", ""), "grand", "canyon") and \
       re.search(r"(july|jul|2019)", data.get("gc_comment", ""), re.I):
        c5 += 2
    else:
        details.append(f"GC comment missing trip/date (got '{data.get('gc_comment', '')}')")
    if _comment_keywords(data.get("pc_comment", ""), "pacific", "coast") and \
       re.search(r"(april|apr|2021)", data.get("pc_comment", ""), re.I):
        c5 += 1
    else:
        details.append(f"PC comment missing trip/date (got '{data.get('pc_comment', '')}')")
    if _comment_keywords(data.get("ne_comment", ""), "new", "england") and \
       re.search(r"(august|aug|2023)", data.get("ne_comment", ""), re.I):
        c5 += 1
    else:
        details.append(f"NE comment missing trip/date (got '{data.get('ne_comment', '')}')")
    score += c5

    passed = score >= 70
    feedback = f"Score: {score}/100. " + ("; ".join(details) if details else "All criteria met.")
    return {"passed": passed, "score": score, "feedback": feedback}
