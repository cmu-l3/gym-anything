#!/usr/bin/env python3
"""
Verifier for restore_trashed_cases task.

Verification strategy:
1. Read exported JSON.
2. For each of the 3 target cases:
   - Must exist in `items` table (not permanently deleted).
   - Must NOT exist in `deletedItems` table (successfully restored).
   - Must retain correct metadata (name check).
3. Check for general data loss (total count should not decrease significantly).

Scoring (100 points):
- Brown v. Board restored: 25 pts
- Miranda v. Arizona restored: 25 pts
- Gideon v. Wainwright restored: 25 pts
- Metadata Integrity (names match): 15 pts
- No Data Loss (no items permanently deleted): 10 pts

Pass threshold: 60 points (Must restore at least 2 items fully).
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_restore_trashed_cases(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that trashed cases were restored to the library."""
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result JSON
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/restore_trashed_cases_result.json", temp.name)
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

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": result["error"]}

    score = 0
    feedback = []
    
    # Helper to score individual items
    def score_item(item_data, name_label):
        pts = 0
        msg = []
        
        # Check existence (Permanent deletion check)
        if item_data.get("exists", 0) != 1:
            msg.append(f"{name_label} was permanently deleted (FAIL)")
            return 0, msg
        
        # Check trash status (Restoration check)
        is_trashed = item_data.get("is_trashed", 1)
        if is_trashed == 0:
            pts += 25
            msg.append(f"{name_label} restored successfully (+25)")
        else:
            msg.append(f"{name_label} is still in Trash")
            
        return pts, msg

    # Score cases
    brown_pts, brown_msg = score_item(result.get("brown", {}), "Brown v. Board")
    miranda_pts, miranda_msg = score_item(result.get("miranda", {}), "Miranda v. Arizona")
    gideon_pts, gideon_msg = score_item(result.get("gideon", {}), "Gideon v. Wainwright")
    
    score += brown_pts + miranda_pts + gideon_pts
    feedback.extend(brown_msg)
    feedback.extend(miranda_msg)
    feedback.extend(gideon_msg)

    # Metadata Integrity (15 pts total, 5 each)
    meta_pts = 0
    if "Brown" in result.get("brown", {}).get("name", ""): meta_pts += 5
    if "Miranda" in result.get("miranda", {}).get("name", ""): meta_pts += 5
    if "Gideon" in result.get("gideon", {}).get("name", ""): meta_pts += 5
    
    if meta_pts == 15:
        score += 15
        feedback.append("Metadata integrity verified (+15)")
    elif meta_pts > 0:
        score += meta_pts
        feedback.append(f"Partial metadata integrity (+{meta_pts})")

    # Data Loss Check (10 pts)
    # If current total >= initial active + 3 (since we started with them in trash in setup? 
    # Actually, setup recorded INITIAL_ACTIVE_COUNT excluding trash.
    # We want to ensure the USER didn't delete OTHER things.
    # A simple check: Current Total Items >= Initial Active Items.
    init_active = result.get("initial_active_count", 0)
    curr_active = result.get("current_active_count", 0)
    
    # Ideally, if all restored, curr_active should be init_active + 3
    # If user deleted something else, curr_active would be lower.
    # We'll just check that we haven't lost a massive amount of data
    if curr_active >= init_active:
        score += 10
        feedback.append("No data loss detected (+10)")
    else:
        feedback.append("Warning: Total item count decreased (possible data loss)")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }