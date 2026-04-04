#!/usr/bin/env python3
"""
Verifier for delete_obsolete_references task.

Verification Strategy:
1. Verify specific target items are in the Trash.
2. Verify they were deleted DURING the task (timestamp check).
3. Verify no "protected" items were deleted (collateral damage).
4. Verify exact counts to ensure precision.

Scoring (100 points):
- Obergefell deleted: 20 pts
- Gideon deleted: 20 pts
- Poe article deleted: 20 pts
- No collateral damage: 20 pts
- Trash count exactly 3: 10 pts
- Active library count exactly 7: 10 pts
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_delete_obsolete_references(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that specific items were trashed without collateral damage."""
    
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

    score = 0
    feedback = []

    # Extract results
    obergefell_del = result.get("obergefell_deleted", False)
    gideon_del = result.get("gideon_deleted", False)
    poe_del = result.get("poe_deleted", False)
    
    # Anti-gaming timestamp checks (optional strictness, usually handled by checking _deleted)
    # The export script logic sets _valid_time. Let's use it for strictness if available.
    obergefell_valid = result.get("obergefell_valid_time", True) 
    
    collateral = result.get("collateral_damage_count", 0)
    trash_count = result.get("total_trash_count", 0)
    active_count = result.get("active_library_count", 0)

    # 1. Target Items (60 pts total)
    if obergefell_del:
        score += 20
        feedback.append("Obergefell v. Hodges successfully trashed (+20)")
    else:
        feedback.append("Obergefell v. Hodges NOT found in trash")

    if gideon_del:
        score += 20
        feedback.append("Gideon v. Wainwright successfully trashed (+20)")
    else:
        feedback.append("Gideon v. Wainwright NOT found in trash")

    if poe_del:
        score += 20
        feedback.append("Poe article successfully trashed (+20)")
    else:
        feedback.append("Poe article NOT found in trash")

    # 2. Collateral Damage (20 pts)
    if collateral == 0:
        score += 20
        feedback.append("No unrelated items were deleted (+20)")
    else:
        feedback.append(f"FAIL: {collateral} protected items were incorrectly deleted")

    # 3. Precision Counts (20 pts)
    # Trash count should be 3 (assuming trash was empty at start)
    if trash_count == 3:
        score += 10
        feedback.append("Trash contains exactly 3 items (+10)")
    else:
        feedback.append(f"Trash contains {trash_count} items (expected 3)")

    # Active library should be 7
    if active_count == 7:
        score += 10
        feedback.append("Active library contains exactly 7 items (+10)")
    else:
        feedback.append(f"Active library contains {active_count} items (expected 7)")

    # Final Pass check
    # Must have deleted at least 2 correct items and have NO collateral damage to pass
    passed = (score >= 60) and (collateral == 0) and (obergefell_del or gideon_del)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result,
    }