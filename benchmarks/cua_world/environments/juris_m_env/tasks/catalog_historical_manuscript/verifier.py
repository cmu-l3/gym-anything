#!/usr/bin/env python3
"""
Verifier for catalog_historical_manuscript task.

Verifies:
1. A Manuscript item exists and was created during the task.
2. Archive/Repository field matches "Library of Congress".
3. Archive Location matches "James Madison Papers...".
4. Title, Author, and other metadata are correct.

"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_catalog_historical_manuscript(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
        os.unlink(temp.name)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to load task result JSON."}

    # Metadata expectations
    meta = task_info.get('metadata', {})
    exp_title = meta.get('expected_title', "Notes of Debates in the Federal Convention of 1787")
    exp_archive = meta.get('expected_archive', "Library of Congress")
    exp_loc = meta.get('expected_location', "James Madison Papers, Series 1, Box 1")
    exp_author_last = meta.get('expected_author_last', "Madison")
    
    score = 0
    max_score = 100
    feedback = []

    # Check 1: Item Created (20 pts)
    if result.get('item_found'):
        score += 20
        feedback.append("New Manuscript item found (+20).")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No new Manuscript item found in the library. Ensure you create a 'Manuscript' item type."
        }

    # Check 2: Archive Data (20 pts)
    # The internal field might be 'repository' or 'archive', script handles this.
    actual_archive = result.get('archive', '')
    if exp_archive.lower() in actual_archive.lower():
        score += 20
        feedback.append(f"Archive field correct: '{actual_archive}' (+20).")
    else:
        feedback.append(f"Archive field mismatch. Expected '{exp_archive}', got '{actual_archive}'.")

    # Check 3: Location Data (20 pts)
    actual_loc = result.get('location', '')
    # Allow partial match for "James Madison Papers" or "Series 1"
    if "madison papers" in actual_loc.lower() or "series 1" in actual_loc.lower():
        score += 20
        feedback.append(f"Location in Archive correct: '{actual_loc}' (+20).")
    else:
        feedback.append(f"Location field mismatch. Expected '{exp_loc}', got '{actual_loc}'.")

    # Check 4: Metadata (Title, Date, Author) (20 pts)
    actual_title = result.get('title', '')
    actual_author = result.get('author_last', '')
    
    meta_score = 0
    if "notes of debates" in actual_title.lower():
        meta_score += 10
    if exp_author_last.lower() in actual_author.lower():
        meta_score += 10
    
    score += meta_score
    if meta_score == 20:
        feedback.append("Title and Author correct (+20).")
    else:
        feedback.append(f"Metadata issues. Title: '{actual_title}', Author: '{actual_author}'.")

    # Check 5: Item Type Specifics (Place, Manuscript Type) (20 pts)
    actual_type = result.get('manuscript_type', '')
    actual_place = result.get('place', '')
    
    type_score = 0
    if "autograph" in actual_type.lower():
        type_score += 10
    if "philadelphia" in actual_place.lower():
        type_score += 10
        
    score += type_score
    feedback.append(f"Place/Type check: Place='{actual_place}', Type='{actual_type}' (+{type_score}).")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }