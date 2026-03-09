#!/usr/bin/env python3
"""
Verifier for rename_tag_globally task.

Scoring Criteria (100 points total):
1. New tag "Equal Protection Clause" exists (40 pts)
2. New tag is associated with the correct number of items (30 pts)
   - Checks that count matches original tag count (should be 3)
3. Old tag "Equal Protection" is gone or empty (20 pts)
4. Specific item integrity (10 pts)
   - Verifies the EXACT items that had the old tag now have the new tag
   - Prevents gaming by just creating a new tag and tagging random items

Anti-gaming:
- Checks if database was modified after task start
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rename_tag_globally(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that the tag was renamed globally in the library."""
    
    # 1. Retrieve Result JSON
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/task_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        logger.error(f"Failed to retrieve result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve export result: {e}. Was the task completed?",
        }

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": result["error"]}

    # 2. Extract Metrics
    new_tag_exists = result.get("new_tag_exists", False)
    new_tag_count = result.get("new_tag_item_count", 0)
    old_tag_exists = result.get("old_tag_exists", False)
    old_tag_count = result.get("old_tag_item_count", 0)
    migrated_count = result.get("migrated_item_count", 0)
    total_original = result.get("total_original_items", 3)
    db_modified = result.get("db_modified_during_task", False)
    
    score = 0
    feedback = []
    
    # 3. Apply Scoring Logic
    
    # Criterion 1: New tag exists (40 pts)
    if new_tag_exists:
        score += 40
        feedback.append("Success: Tag 'Equal Protection Clause' found (+40)")
    else:
        feedback.append("Failed: Tag 'Equal Protection Clause' NOT found")
        # Critical failure, though we check other things for partial feedback
        
    # Criterion 2: Correct item count (30 pts)
    # We expect 3 items. Allow match if count == total_original
    if new_tag_count == total_original and total_original > 0:
        score += 30
        feedback.append(f"Success: New tag has {new_tag_count} items (+30)")
    elif new_tag_count > 0:
        # Partial credit if they created tag but didn't get all items (maybe manual tagging?)
        score += 15
        feedback.append(f"Partial: New tag has {new_tag_count} items, expected {total_original} (+15)")
    else:
        feedback.append("Failed: New tag has 0 items")

    # Criterion 3: Old tag removed/empty (20 pts)
    if old_tag_count == 0:
        score += 20
        feedback.append("Success: Old tag 'Equal Protection' is gone or empty (+20)")
    else:
        feedback.append(f"Failed: Old tag still has {old_tag_count} items attached")

    # Criterion 4: Item Integrity (10 pts)
    # Did the *correct* items get the tag?
    if migrated_count == total_original and total_original > 0:
        score += 10
        feedback.append("Success: All original items were correctly migrated (+10)")
    elif migrated_count > 0:
        score += 5
        feedback.append(f"Partial: {migrated_count}/{total_original} items migrated (+5)")
    
    # Anti-gaming check
    if not db_modified and score > 0:
        feedback.append("Warning: Database not modified during task (possible gaming)")
        # We don't zero the score here but note it. 
        # In a strict environment, we might cap score at 0.
        
    # Final Calculation
    passed = (score >= 70) and new_tag_exists and (old_tag_count == 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }