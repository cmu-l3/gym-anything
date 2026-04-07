#!/usr/bin/env python3
"""
Verifier for finalize_tentative_schedule task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_finalize_tentative_schedule(traj, env_info, task_info):
    """
    Verify the agent correctly finalized the meeting schedule:
    1. Tuesday and Thursday tentative slots are deleted.
    2. Wednesday slot is preserved.
    3. Wednesday slot is renamed to remove "Hold: ".
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
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
    
    if not result.get("setup_valid"):
        return {"passed": False, "score": 0, "feedback": "Task setup verification failed (IDs missing)."}

    # 1. Verify Tuesday Slot Deleted (20 pts)
    # It counts as deleted if it doesn't exist OR if active is False
    tue_exists = result.get("tue_exists")
    tue_active = result.get("tue_active", True)
    
    if not tue_exists or not tue_active:
        score += 20
        feedback_parts.append("Tuesday slot deleted (+20)")
    else:
        feedback_parts.append("Tuesday slot still active")

    # 2. Verify Thursday Slot Deleted (20 pts)
    thu_exists = result.get("thu_exists")
    thu_active = result.get("thu_active", True)
    
    if not thu_exists or not thu_active:
        score += 20
        feedback_parts.append("Thursday slot deleted (+20)")
    else:
        feedback_parts.append("Thursday slot still active")

    # 3. Verify Wednesday Slot Preserved (20 pts)
    wed_exists = result.get("wed_exists")
    wed_data = result.get("wed_data", {})
    wed_active = wed_data.get("active", True)
    
    if wed_exists and wed_active:
        score += 20
        feedback_parts.append("Wednesday slot preserved (+20)")
        
        # 4. Verify Rename (30 pts)
        # Should be "Q3 Budget Review", NOT "Hold: Q3 Budget Review"
        name = wed_data.get("name", "").strip()
        if name == "Q3 Budget Review":
            score += 30
            feedback_parts.append("Meeting renamed correctly (+30)")
        elif "Hold" in name:
            feedback_parts.append(f"Meeting name still contains 'Hold': '{name}'")
        else:
            feedback_parts.append(f"Meeting name incorrect: '{name}'")
            
        # 5. Verify Time (10 pts)
        # We check exact string match from Odoo's return vs expected
        actual_start = wed_data.get("start")
        expected_start = result.get("expected_wed_start")
        
        if actual_start == expected_start:
            score += 10
            feedback_parts.append("Time preserved exactly (+10)")
        else:
            # Fallback: lenient check if the date and hour match (ignore seconds/formatting diffs)
            # This handles cases where Odoo might return varying formats slightly
            if expected_start and actual_start and expected_start[:13] == actual_start[:13]:
                score += 10
                feedback_parts.append("Time preserved (+10)")
            else:
                feedback_parts.append(f"Time changed! Expected {expected_start}, got {actual_start}")

    else:
        feedback_parts.append("Wednesday slot was deleted! (Fail)")
        # If the winner is deleted, they probably deleted all 3 and created a new one.
        # We penalize this heavily because the task is about "Finalizing" (modifying), not re-creating.
        # But if they created a NEW event with correct details, we should probably check that to be fair?
        # The prompt says "Delete unused... Rename the confirmed...".
        # If they deleted all and created new, they failed the "Rename" instruction.
        pass

    # Anti-gaming check
    remaining_holds = result.get("remaining_holds_count", 0)
    if remaining_holds > 0:
        score = max(0, score - (remaining_holds * 10))
        feedback_parts.append(f"Penalty: {remaining_holds} 'Hold' events still exist (-{remaining_holds * 10})")

    # Final result
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }