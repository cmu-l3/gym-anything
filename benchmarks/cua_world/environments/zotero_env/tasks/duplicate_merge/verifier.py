#!/usr/bin/env python3
"""
Verifier for duplicate_merge task.

Task: The library has 10 neuroscience papers each duplicated (20 items total).
Each copy A has a child note. Merge all duplicates so exactly one copy remains
per paper, preserving the note.

Scoring (100 points):
  - No duplicate titles remaining (30 pts, 3 each for 10 papers)
  - Total item count reduced to ~10 (20 pts)
  - Notes preserved on surviving copies (40 pts, 4 each for 10 papers)
  - All 10 expected papers still exist (10 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_duplicate_merge(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/duplicate_merge_result.json", tmp.name)
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

    items_by_title = result.get("items_by_title", {})
    notes_preserved = result.get("notes_preserved", {})
    duplicate_titles = result.get("duplicate_titles", [])
    current_count = result.get("current_item_count", 0)

    # Criterion 1: No duplicates remaining (30 pts, 3 each)
    no_dup_count = sum(
        1 for title, ids in items_by_title.items() if len(ids) <= 1
    )
    dup_pts = no_dup_count * 3
    score += dup_pts
    subscores["papers_deduplicated"] = f"{no_dup_count}/10"
    if len(duplicate_titles) == 0:
        feedback_parts.append("All 10 duplicate sets merged")
    else:
        feedback_parts.append(f"Duplicates merged: {no_dup_count}/10 (still duplicated: {len(duplicate_titles)})")

    # Criterion 2: Total item count near 10 (20 pts)
    if current_count <= 12:
        score += 20
        subscores["item_count_ok"] = True
        feedback_parts.append(f"Item count reduced to {current_count} (≤12)")
    elif current_count <= 15:
        score += 10
        subscores["item_count_ok"] = "partial"
        feedback_parts.append(f"Item count {current_count} (partially reduced, expect ~10)")
    else:
        subscores["item_count_ok"] = False
        feedback_parts.append(f"Item count {current_count} — duplicates not merged")

    # Criterion 3: Notes preserved (40 pts, 4 each)
    notes_ok = sum(1 for v in notes_preserved.values() if v)
    notes_pts = notes_ok * 4
    score += notes_pts
    subscores["notes_preserved"] = f"{notes_ok}/10"
    if notes_ok == 10:
        feedback_parts.append("All 10 paper notes preserved after merge")
    else:
        feedback_parts.append(f"Notes preserved: {notes_ok}/10")

    # Criterion 4: All 10 expected papers still present (10 pts)
    present_count = sum(1 for ids in items_by_title.values() if len(ids) >= 1)
    if present_count == 10:
        score += 10
        subscores["all_papers_present"] = True
        feedback_parts.append("All 10 papers still present")
    else:
        subscores["all_papers_present"] = False
        feedback_parts.append(f"Only {present_count}/10 papers still present (some accidentally deleted?)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
