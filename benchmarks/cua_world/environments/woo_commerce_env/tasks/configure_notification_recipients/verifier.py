#!/usr/bin/env python3
"""
Verifier for Configure Notification Recipients task.

Verification Strategy:
1. Programmatic (85 points): 
   - Check if recipients match expected values exactly.
   - Verify the admin email was removed (anti-lazy check).
   - Confirm values actually changed from start.
2. VLM (15 points):
   - Check trajectory for navigation to Emails settings tab.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_notification_recipients(traj, env_info, task_info):
    """
    Verify email notification recipients were updated correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_new = metadata.get('expected_new_order', 'fulfillment@example.com')
    expected_cancelled = metadata.get('expected_cancelled_order', 'accounting@example.com')
    expected_failed = metadata.get('expected_failed_order', 'sysadmin@example.com')
    forbidden = metadata.get('forbidden_recipient', 'admin@example.com')

    # Load result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": "Task failed: Database unreachable"}

    score = 0
    feedback = []

    # Get actual values
    actual_new = result.get("new_order_recipient", "").strip()
    actual_cancelled = result.get("cancelled_order_recipient", "").strip()
    actual_failed = result.get("failed_order_recipient", "").strip()

    # Criterion 1: New Order Recipient (25 pts)
    if actual_new == expected_new:
        score += 25
        feedback.append("New Order recipient correct.")
    elif expected_new in actual_new:
        score += 10
        feedback.append(f"New Order recipient contains target but has extras: '{actual_new}'.")
    else:
        feedback.append(f"New Order recipient incorrect. Expected: {expected_new}, Got: {actual_new}.")

    # Criterion 2: Cancelled Order Recipient (25 pts)
    if actual_cancelled == expected_cancelled:
        score += 25
        feedback.append("Cancelled Order recipient correct.")
    elif expected_cancelled in actual_cancelled:
        score += 10
        feedback.append(f"Cancelled recipient contains target but has extras: '{actual_cancelled}'.")
    else:
        feedback.append(f"Cancelled recipient incorrect. Expected: {expected_cancelled}, Got: {actual_cancelled}.")

    # Criterion 3: Failed Order Recipient (25 pts)
    if actual_failed == expected_failed:
        score += 25
        feedback.append("Failed Order recipient correct.")
    elif expected_failed in actual_failed:
        score += 10
        feedback.append(f"Failed recipient contains target but has extras: '{actual_failed}'.")
    else:
        feedback.append(f"Failed recipient incorrect. Expected: {expected_failed}, Got: {actual_failed}.")

    # Criterion 4: Admin Removal (10 pts)
    # Check if admin email is present in ANY of the fields
    admin_present = False
    if forbidden in actual_new or forbidden in actual_cancelled or forbidden in actual_failed:
        admin_present = True
    
    if not admin_present:
        score += 10
        feedback.append("Admin email successfully removed from all modified fields.")
    else:
        feedback.append(f"Admin email ({forbidden}) still present in one or more fields.")

    # Criterion 5: Change Detection (Anti-Gaming) (15 pts)
    # Ensure the agent didn't just type nothing or leave defaults (though defaults were checked above)
    changed = result.get("changed_new") and result.get("changed_cancelled") and result.get("changed_failed")
    if changed:
        score += 15
        feedback.append("Settings were modified during task.")
    else:
        feedback.append("One or more settings were NOT modified from initial state.")

    passed = (score >= 90)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }