#!/usr/bin/env python3
"""
Verifier for hierarchical_reorganization task.

Task: Reorganize 30 papers from "Unsorted Import" into a "Research Archive"
collection with 4 subcollections by decade:
  Pre-1960, 1960-1999, 2000-2010, Post-2010
Then delete the original "Unsorted Import" collection.

Expected counts: Pre-1960: 8, 1960-1999: 10, 2000-2010: 7, Post-2010: 5

Scoring (100 points):
  - Parent "Research Archive" exists: 10 pts
  - All 4 subcollections exist under parent: 20 pts (5 each)
  - Papers correctly sorted (no misplacements): 40 pts
    (1.33 pts each paper, scaled to 40)
  - "Unsorted Import" deleted: 10 pts
  - Total papers organized = 30: 20 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

EXPECTED_COUNTS = {
    "Pre-1960": 8,
    "1960-1999": 10,
    "2000-2010": 7,
    "Post-2010": 5,
}


def verify_hierarchical_reorganization(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/hierarchical_reorganization_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may have failed"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Copy/parse error: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # Criterion 1: Parent "Research Archive" exists (10 pts)
    if result.get("parent_collection_exists"):
        score += 10
        subscores["parent_exists"] = True
        feedback_parts.append("'Research Archive' collection exists")
    else:
        subscores["parent_exists"] = False
        feedback_parts.append("'Research Archive' collection NOT found")

    # Criterion 2: All 4 subcollections exist (20 pts, 5 each)
    subcollections = result.get("subcollections", {})
    existing_subcolls = [name for name, info in subcollections.items() if info.get("exists")]
    subcoll_pts = len(existing_subcolls) * 5
    score += subcoll_pts
    subscores["subcollections_exist"] = f"{len(existing_subcolls)}/4"
    if len(existing_subcolls) == 4:
        feedback_parts.append("All 4 decade subcollections exist")
    else:
        missing = [n for n in EXPECTED_COUNTS if n not in existing_subcolls]
        feedback_parts.append(f"Subcollections: {len(existing_subcolls)}/4 (missing: {missing})")

    # Criterion 3: Papers correctly sorted — no misplacements (40 pts)
    misplaced = result.get("papers_in_wrong_bucket", [])
    total_organized = result.get("total_organized", 0)
    correctly_placed = total_organized - len(misplaced)
    if total_organized > 0:
        sort_ratio = correctly_placed / 30  # out of expected 30 total
        sort_pts = int(sort_ratio * 40)
    else:
        sort_pts = 0
    score += sort_pts
    subscores["correct_placements"] = f"{correctly_placed}/30"
    subscores["misplaced_count"] = len(misplaced)
    if len(misplaced) == 0 and total_organized >= 28:
        feedback_parts.append(f"All {total_organized} papers correctly placed in decade buckets")
    elif len(misplaced) == 0:
        feedback_parts.append(f"{total_organized}/30 papers placed (all in correct buckets)")
    else:
        feedback_parts.append(f"{correctly_placed}/30 correctly placed ({len(misplaced)} in wrong decade bucket)")

    # Criterion 4: "Unsorted Import" deleted (10 pts)
    if result.get("source_collection_deleted"):
        score += 10
        subscores["source_deleted"] = True
        feedback_parts.append("'Unsorted Import' collection deleted")
    else:
        subscores["source_deleted"] = False
        feedback_parts.append("'Unsorted Import' collection still exists")

    # Criterion 5: Total organized = 30 (20 pts)
    if total_organized == 30:
        score += 20
        subscores["total_organized"] = 30
        feedback_parts.append("All 30 papers organized")
    elif total_organized >= 25:
        score += 10
        subscores["total_organized"] = total_organized
        feedback_parts.append(f"Partially organized: {total_organized}/30 papers")
    else:
        subscores["total_organized"] = total_organized
        feedback_parts.append(f"Only {total_organized}/30 papers moved to subcollections")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
