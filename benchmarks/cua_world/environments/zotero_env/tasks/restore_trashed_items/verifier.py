#!/usr/bin/env python3
"""
Verifier for restore_trashed_items task.

Scoring Breakdown (100 points total):
1. Restoration (50 pts): 10 pts for each of the 5 papers removed from Trash.
2. Organization (40 pts): 8 pts for each of the 5 papers added to "Thesis References".
3. Safety (10 pts): 10 pts if all 3 original papers remain in the collection (Collateral Damage check).

Pass Threshold: 60 points.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_restore_trashed_items(traj, env_info, task_info):
    """Verify that papers were restored and organized."""
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 2. Extract Data
    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Task Error: {result['error']}"}

    restored_status = result.get("restored_status", {})
    collection_status = result.get("collection_status", {})
    collateral_damage = result.get("collateral_damage", {})
    counts = result.get("counts", {})

    score = 0
    feedback_parts = []
    
    # 3. Score Restoration (Max 50)
    restored_count = counts.get("restored", 0)
    score += (restored_count * 10)
    if restored_count == 5:
        feedback_parts.append("All 5 papers restored from Trash (50 pts)")
    elif restored_count > 0:
        feedback_parts.append(f"{restored_count}/5 papers restored from Trash ({restored_count*10} pts)")
    else:
        feedback_parts.append("No papers restored")

    # 4. Score Organization (Max 40)
    organized_count = counts.get("organized", 0)
    score += (organized_count * 8)
    if organized_count == 5:
        feedback_parts.append("All 5 papers added to collection (40 pts)")
    elif organized_count > 0:
        feedback_parts.append(f"{organized_count}/5 papers added to collection ({organized_count*8} pts)")
    else:
        feedback_parts.append("No restored papers added to collection")

    # 5. Score Safety (Max 10)
    # Check if all 3 original papers are still present
    original_kept = counts.get("kept", 0)
    total_originals = len(collateral_damage) if collateral_damage else 3
    
    if original_kept == total_originals and total_originals > 0:
        score += 10
        feedback_parts.append("Existing collection items preserved (10 pts)")
    else:
        missing = total_originals - original_kept
        feedback_parts.append(f"Warning: {missing} original papers were removed from collection (0 pts)")

    # 6. Final Evaluation
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }