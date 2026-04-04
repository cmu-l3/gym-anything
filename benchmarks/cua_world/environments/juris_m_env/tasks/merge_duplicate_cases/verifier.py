#!/usr/bin/env python3
"""
Verifier for merge_duplicate_cases task.
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_merge_duplicate_cases(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """
    Verify that duplicates were merged correctly and the correct metadata was preserved.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON
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
            "feedback": f"Could not retrieve export result: {e}"
        }

    score = 0
    feedback = []

    # 1. Active Item Count (Target: 10) - 25 pts
    active_count = result.get("active_item_count", 0)
    if active_count == 10:
        score += 25
        feedback.append("Correct final item count (10) (+25)")
    else:
        feedback.append(f"Incorrect item count: {active_count} (Expected 10)")

    # 2. Duplicate Groups (Target: 0) - 20 pts
    dup_groups = result.get("duplicate_groups_count", 99)
    if dup_groups == 0:
        score += 20
        feedback.append("No duplicate case names remaining (+20)")
    else:
        feedback.append(f"Found {dup_groups} pair(s) of duplicates remaining")

    # 3. Deleted Items Increase (Target: >=3) - 15 pts
    deleted_diff = result.get("deleted_items_increase", 0)
    if deleted_diff >= 3:
        score += 15
        feedback.append("Merged items successfully moved to trash (+15)")
    else:
        feedback.append(f"Only {deleted_diff} items deleted (Expected >= 3 merged)")

    # 4. Metadata Integrity - 30 pts (10 pts each)
    metadata = result.get("metadata_checks", {})
    
    # Check Brown v. Board abstract (should be long version)
    brown_abs = metadata.get("brown_abstract", "")
    if "overturning Plessy" in brown_abs:
        score += 10
        feedback.append("Brown v. Board preserved full abstract (+10)")
    else:
        feedback.append("Brown v. Board has truncated or missing abstract")

    # Check Miranda abstract (should exist)
    miranda_abs = metadata.get("miranda_abstract", "")
    if len(miranda_abs) > 10:
        score += 10
        feedback.append("Miranda v. Arizona preserved abstract (+10)")
    else:
        feedback.append("Miranda v. Arizona missing abstract")

    # Check Gideon court (should exist)
    gideon_court = metadata.get("gideon_court", "")
    if "Supreme Court" in gideon_court:
        score += 10
        feedback.append("Gideon v. Wainwright preserved court field (+10)")
    else:
        feedback.append("Gideon v. Wainwright missing court field")
        
    # 5. Anti-gaming check
    # If duplicates were removed but count is wrong (e.g., deleted everything), penalty
    if active_count < 5:
        score = 0
        feedback.append("CRITICAL: Too many items deleted. Library destroyed.")

    passed = (score >= 60 and active_count == 10)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }