#!/usr/bin/env python3
"""
Verifier for cleanup_stale_branches task.

Scoring (100 points total):
- 15 points for each stale branch deleted (5 * 15 = 75)
- 8 points for preserving 'main'
- 8 points for preserving 'develop'
- 9 points for preserving 'release/v1.0'

Pass threshold: 70 points (Must delete at least 4 stale branches AND keep all active ones)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cleanup_stale_branches(traj, env_info, task_info):
    """
    Verify that stale branches were deleted and active branches preserved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define expectations
    expected_to_delete = [
        "feature/search-api",
        "feature/user-auth",
        "bugfix/price-calc",
        "feature/old-dashboard",
        "feature/experimental-cache"
    ]
    
    expected_to_keep = ["main", "develop", "release/v1.0"]

    # Load result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Windows path in container is mapped to local temp file
        copy_from_env("C:/Users/Docker/task_results/cleanup_stale_branches_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Check Deleted Branches (75 points max)
    deleted_correctly_map = result.get("deleted_correctly", {})
    deleted_count = 0
    
    for branch in expected_to_delete:
        if deleted_correctly_map.get(branch, False):
            score += 15
            deleted_count += 1
            feedback_parts.append(f"Deleted {branch} (+15)")
        else:
            feedback_parts.append(f"FAILED to delete {branch}")

    # Check Kept Branches (25 points max)
    kept_correctly_map = result.get("kept_correctly", {})
    kept_all_active = True
    
    # Weighted slightly differently to sum to 25
    keep_weights = {"main": 8, "develop": 8, "release/v1.0": 9}
    
    for branch in expected_to_keep:
        if kept_correctly_map.get(branch, False):
            points = keep_weights.get(branch, 8)
            score += points
            feedback_parts.append(f"Preserved {branch} (+{points})")
        else:
            kept_all_active = False
            feedback_parts.append(f"ACCIDENTALLY DELETED {branch} (Critical Fail)")

    # Anti-gaming check: If final count equals initial count, they did nothing
    initial_count = result.get("initial_count", 0)
    final_count = result.get("final_count", 0)
    
    if initial_count > 0 and initial_count == final_count:
        score = 0
        feedback_parts = ["Agent did nothing (branch count unchanged)"]
        return {"passed": False, "score": 0, "feedback": "Agent did nothing"}

    # Pass Criteria
    # Must preserve active branches to pass
    # Must delete at least 4/5 stale branches
    passed = (score >= 70) and kept_all_active and (deleted_count >= 4)
    
    if not kept_all_active:
        score = min(score, 60) # Penalty cap if active branch deleted

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }