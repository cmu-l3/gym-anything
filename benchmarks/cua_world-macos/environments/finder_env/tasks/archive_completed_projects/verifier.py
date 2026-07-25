"""Verifier for finder_env's archive_completed_projects task.

Scoring (100 points, pass at 70):
- 30 pts  C1 (active_present)   Active projects (HomeRenovation, LearnPiano) still
                                  exist in Projects/ with Green tag (10+5 each).
- 30 pts  C2 (archive_zips)     Done project zip files exist in Archive/ (10 each).
- 20 pts  C3 (originals_gone)   Done project folders deleted from Projects/ (7+7+6).
- 20 pts  C4 (zip_comments)     Zip Finder comments contain 'archived' + '2026' (7+7+6).
"""
from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict

logger = logging.getLogger(__name__)

ACTIVE_PROJECTS = ["HomeRenovation", "LearnPiano"]
DONE_PROJECTS = ["VegetableGarden", "BookClub2024", "CookingChallenge"]
REMOTE_RESULT = "/tmp/archive_completed_projects_result.json"


def verify_archive_completed_projects(
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

    # C1: Active projects present with Green tag (30 pts — 15 each: 10 presence + 5 tag)
    c1 = 0
    for name in ACTIVE_PROJECTS:
        if data.get("active_folders_exist", {}).get(name):
            c1 += 10
            tags = data.get("active_tags", {}).get(name, [])
            if "Green" in tags:
                c1 += 5
            else:
                details.append(f"{name}: present but missing Green tag (got {tags})")
        else:
            details.append(f"Active project {name} was deleted — should remain in place")
    score += c1

    # C2: Done project zips in Archive (30 pts — 10 each)
    c2 = 0
    archive_zips: set = set(data.get("archive_zips", []))
    for name in DONE_PROJECTS:
        if f"{name}.zip" in archive_zips:
            c2 += 10
        else:
            details.append(f"Missing zip in Archive: {name}.zip")
    score += c2

    # C3: Done originals deleted (20 pts — 7+7+6)
    pts_per = [7, 7, 6]
    c3 = 0
    for i, name in enumerate(DONE_PROJECTS):
        if not data.get("done_folders_exist", {}).get(name, True):
            c3 += pts_per[i]
        else:
            details.append(f"Done project {name} was not deleted from Projects/")
    score += c3

    # C4: Zip comments contain 'archived' + '2026' (20 pts — 7+7+6)
    c4 = 0
    zip_comments: dict = data.get("zip_comments", {})
    for i, name in enumerate(DONE_PROJECTS):
        comment = zip_comments.get(f"{name}.zip", "").lower()
        if "archived" in comment and "2026" in comment:
            c4 += pts_per[i]
        else:
            details.append(f"{name}.zip: comment missing 'archived'/'2026' (got '{comment}')")
    score += c4

    passed = score >= 70
    feedback = f"Score: {score}/100. " + ("; ".join(details) if details else "All criteria met.")
    return {"passed": passed, "score": score, "feedback": feedback}
