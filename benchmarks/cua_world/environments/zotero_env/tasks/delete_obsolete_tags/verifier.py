#!/usr/bin/env python3
"""
Verifier for delete_obsolete_tags task.

Scoring:
- Each junk tag deleted: 8 points (6 tags * 8 = 48)
- Each good tag preserved: 8 points (5 tags * 8 = 40)
- All items preserved: 12 points
- Total: 100 points
- Pass Threshold: 75 points

Anti-gaming:
- If all tags (junk + good) are deleted, score will be 48 + 0 + 12 = 60 -> FAIL.
- If no tags are deleted, score will be 0 + 40 + 12 = 52 -> FAIL.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_delete_obsolete_tags(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if not result.get("db_accessible", False):
        return {"passed": False, "score": 0, "feedback": "Could not access Zotero database to verify results."}

    score = 0
    feedback_parts = []
    
    # 1. Verify Junk Tags Deleted (6 tags * 8 pts = 48)
    junk_status = result.get("junk_tags_status", {})
    junk_deleted_count = 0
    
    for tag, status in junk_status.items():
        if not status["exists_in_db"]:
            score += 8
            junk_deleted_count += 1
        else:
            feedback_parts.append(f"Junk tag '{tag}' NOT deleted")
            
    if junk_deleted_count == 6:
        feedback_parts.append("All junk tags deleted")
    elif junk_deleted_count > 0:
        feedback_parts.append(f"{junk_deleted_count}/6 junk tags deleted")

    # 2. Verify Good Tags Preserved (5 tags * 8 pts = 40)
    good_status = result.get("good_tags_status", {})
    good_preserved_count = 0
    
    for tag, status in good_status.items():
        # Tag must exist AND have at least one item
        if status["exists_in_db"] and status["item_count"] > 0:
            score += 8
            good_preserved_count += 1
        else:
            if not status["exists_in_db"]:
                feedback_parts.append(f"Good tag '{tag}' was DELETED")
            else:
                feedback_parts.append(f"Good tag '{tag}' exists but has 0 items")
                
    if good_preserved_count == 5:
        feedback_parts.append("All topic tags preserved")
    elif good_preserved_count > 0:
        feedback_parts.append(f"{good_preserved_count}/5 topic tags preserved")

    # 3. Verify Items Preserved (12 pts)
    # Anti-gaming check: deleting items usually deletes tags, so this penalizes mass deletion
    initial_count = result.get("initial_item_count", 0)
    final_count = result.get("final_item_count", 0)
    
    if result.get("items_preserved", False):
        score += 12
        feedback_parts.append("Library items preserved")
    else:
        diff = initial_count - final_count
        if diff > 0:
            feedback_parts.append(f"WARNING: {diff} items were deleted!")
        else:
            feedback_parts.append(f"Item count changed ({initial_count} -> {final_count})")

    # 4. Anti-gaming: Check if user did NOTHING
    initial_tag_count = result.get("initial_tag_count", 0)
    final_tag_count = result.get("final_tag_count", 0)
    
    if initial_tag_count == final_tag_count and junk_deleted_count == 0:
        feedback_parts.append("No changes detected in tag count.")
    
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "junk_deleted": junk_deleted_count,
            "good_preserved": good_preserved_count,
            "items_preserved": result.get("items_preserved", False)
        }
    }