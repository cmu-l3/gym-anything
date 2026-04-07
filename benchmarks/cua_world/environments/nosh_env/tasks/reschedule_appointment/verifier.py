#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reschedule_appointment(traj, env_info, task_info):
    """
    Verify that Michael Chang's appointment was rescheduled correctly.
    
    Criteria:
    1. New Slot Occupied (50 pts): Appointment exists at the requested time.
    2. Old Slot Cleared (30 pts): No active appointment at the original time.
    3. Reason Updated (20 pts): Reason contains 'conflict' or 'work'.
    """
    
    # 1. Setup - Get Result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    new_slot = result.get('new_slot', {})
    new_count = new_slot.get('count', 0)
    new_reason = new_slot.get('reason', '').lower()
    
    old_slot_count = result.get('old_slot_count', 0)
    target_dt = result.get('target_datetime', 'Unknown')
    
    score = 0
    feedback_parts = []
    
    # 3. Evaluate Criteria
    
    # Criterion 1: Target Slot Occupied (50 pts)
    if new_count >= 1:
        score += 50
        feedback_parts.append(f"✅ Appointment found at {target_dt}")
    else:
        feedback_parts.append(f"❌ No appointment found at {target_dt}")

    # Criterion 2: Old Slot Cleared (30 pts)
    if old_slot_count == 0:
        score += 30
        feedback_parts.append("✅ Old appointment slot is clear")
    else:
        feedback_parts.append("❌ Old appointment slot is still active (Double booked?)")

    # Criterion 3: Reason Updated (20 pts)
    # Only check if we actually found the new appointment
    if new_count >= 1:
        if "conflict" in new_reason or "work" in new_reason:
            score += 20
            feedback_parts.append(f"✅ Reason updated correctly ('{new_reason}')")
        elif new_reason == "routine checkup":
            feedback_parts.append("⚠️ Reason not updated (still 'Routine Checkup')")
        else:
            # Partial credit for changing it to something else
            score += 10
            feedback_parts.append(f"⚠️ Reason changed but didn't match keywords ('{new_reason}')")

    # 4. Final Verdict
    # Pass if score >= 80 (Needs Correct Time + Clean Schedule)
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }