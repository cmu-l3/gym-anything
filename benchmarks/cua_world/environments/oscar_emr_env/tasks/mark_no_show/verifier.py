#!/usr/bin/env python3
"""
Verifier for mark_no_show task in Oscar EMR.
Verifies that the specific appointment status was changed to 'N' (No Show)
and checks for anti-gaming timestamps and collateral damage.
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mark_no_show(traj, env_info, task_info):
    """
    Verify the appointment was marked as No Show.
    
    Scoring Criteria:
    1. Status is 'N' (60 pts)
    2. Change happened after task start (15 pts)
    3. Correct appointment target (15 pts)
    4. No collateral damage (other appts changed) (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    initial_status = result.get('initial_status', '')
    current_status = result.get('current_status', '')
    task_start = result.get('task_start_time', 0)
    last_update = result.get('last_update_time', 0)
    collateral = result.get('collateral_no_shows', 0)
    
    expected_demo = str(result.get('demo_no', ''))
    actual_demo = str(result.get('appt_demo_match', ''))
    expected_date = result.get('today_date', '')
    actual_date = result.get('appt_date_match', '')

    # 1. Status Check (60 pts)
    # Accept 'N', 'NS', or 'n' as valid No Show statuses
    if current_status in ['N', 'NS', 'n']:
        score += 60
        feedback_parts.append("Appointment correctly marked as No Show")
    elif current_status == initial_status:
        feedback_parts.append(f"Status unchanged (still '{current_status}')")
    else:
        # Partial credit for changing status, but to wrong thing
        score += 15
        feedback_parts.append(f"Status changed to '{current_status}' (expected 'N')")

    # 2. Anti-Gaming Timestamp Check (15 pts)
    # Check if the update happened after the task started
    if last_update > task_start:
        score += 15
        feedback_parts.append("Update verified as recent")
    elif last_update > 0:
        feedback_parts.append("Warning: Appointment update time predates task start")
    else:
        feedback_parts.append("Could not verify update timestamp")

    # 3. Target Integrity Check (15 pts)
    # Verify we are looking at the correct appointment ID's data
    if actual_demo == expected_demo and actual_date == expected_date:
        score += 15
        feedback_parts.append("Verified correct appointment target")
    else:
        feedback_parts.append("Target mismatch (wrong patient or date)")

    # 4. Collateral Damage Check (10 pts)
    # Ensure no other appointments were incorrectly marked
    if collateral == 0:
        score += 10
        feedback_parts.append("No other appointments affected")
    else:
        feedback_parts.append(f"Warning: {collateral} other appointment(s) also marked No Show")

    # Calculate Pass/Fail
    # Must have correct status AND target integrity
    passed = (current_status in ['N', 'NS', 'n']) and (actual_demo == expected_demo) and (score >= 75)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }