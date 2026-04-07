#!/usr/bin/env python3
"""
Verifier for cleanup_duplicate_event task.

Goal: Delete the duplicate event (no attendees) and keep the valid event (with attendees).

Criteria:
1. Bad Event (ID from setup) must NOT exist. (50 pts)
2. Good Event (ID from setup) MUST exist. (30 pts)
3. Good Event must still have attendees (>=2). (10 pts)
4. Total count of 'Vendor Evaluation' events should be 1. (10 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cleanup_duplicate_event(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check for script errors
    if not result.get("task_setup_valid", False):
        return {"passed": False, "score": 0, "feedback": f"Verification script error: {result.get('error', 'Unknown')}"}

    score = 0
    feedback_parts = []
    
    # 1. Check Bad Event Deletion (50 pts)
    if not result["bad_event_exists"]:
        score += 50
        feedback_parts.append("Duplicate 'ghost' event successfully deleted.")
    else:
        feedback_parts.append("Duplicate event still exists.")

    # 2. Check Good Event Preservation (30 pts)
    if result["good_event_exists"]:
        score += 30
        feedback_parts.append("Valid event preserved.")
        
        # 3. Check Attributes (10 pts)
        # We expect at least Alice and Bob. Odoo adds the creator (admin) sometimes too, so >=2 is safe.
        attendee_count = result.get("good_event_attendee_count", 0)
        if attendee_count >= 2:
            score += 10
            feedback_parts.append(f"Valid event retained attendees (count: {attendee_count}).")
        else:
            feedback_parts.append(f"Valid event missing attendees (count: {attendee_count}).")
    else:
        feedback_parts.append("Valid event was deleted!")

    # 4. Check Total Count (10 pts)
    # This prevents edge cases where agent might delete both and create a new one manually (which would have a different ID)
    # If they did that, good_event_exists would be false, so this helps distinguish partial fail vs total fail.
    # Also catches if they duplicated the good one instead of deleting the bad one.
    total_count = result.get("total_event_count", 0)
    if total_count == 1:
        score += 10
        feedback_parts.append("Calendar clean (exactly 1 event remains).")
    else:
        feedback_parts.append(f"Calendar clutter remains (count: {total_count}).")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }