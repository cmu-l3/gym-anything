#!/usr/bin/env python3
"""
Verifier for delete_vertices task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_delete_vertices(traj, env_info, task_info):
    """
    Verify that the specific hotels were deleted and graph integrity maintained.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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

    score = 0
    feedback_parts = []
    
    # 1. Check Deletions (20 pts each = 60 pts)
    targets = result.get("deleted_targets", {})
    all_deleted = True
    for name, count in targets.items():
        if count == 0:
            score += 20
            feedback_parts.append(f"Deleted '{name}'")
        else:
            all_deleted = False
            feedback_parts.append(f"Failed to delete '{name}' (count: {count})")
            
    # 2. Check Count Decrease (15 pts)
    initial_count = result.get("initial_count", 0)
    final_count = result.get("final_count", 0)
    expected_diff = 3
    actual_diff = initial_count - final_count
    
    if actual_diff == expected_diff:
        score += 15
        feedback_parts.append("Total count decreased by exactly 3")
    elif actual_diff > 0:
        score += 5
        feedback_parts.append(f"Total count decreased by {actual_diff} (expected 3)")
    else:
        feedback_parts.append(f"Total count did not decrease (Initial: {initial_count}, Final: {final_count})")

    # 3. Check Survivors (10 pts)
    survivors = result.get("survivors", {})
    survivors_intact = True
    for name, count in survivors.items():
        if count == 0:
            survivors_intact = False
            feedback_parts.append(f"Wrongly deleted survivor '{name}'")
    
    if survivors_intact and len(survivors) > 0:
        score += 10
        feedback_parts.append("Surviving hotels intact")
    elif not survivors_intact:
        feedback_parts.append("Collateral damage detected")

    # 4. Check Orphaned Edges (10 pts)
    orphans = result.get("orphaned_edges", {})
    total_orphans = sum(orphans.values())
    if total_orphans == 0:
        score += 10
        feedback_parts.append("No orphaned edges (Clean DELETE VERTEX used)")
    else:
        feedback_parts.append(f"Found {total_orphans} orphaned edges (Use DELETE VERTEX, not DELETE FROM)")

    # 5. Workflow Evidence (5 pts)
    # If deletions happened, we assume workflow happened
    if all_deleted:
        score += 5
    elif result.get("task_end", 0) > result.get("task_start", 0):
        # Check screenshot existence as minimal evidence
        score += 5

    passed = (score >= 70) and all_deleted
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }