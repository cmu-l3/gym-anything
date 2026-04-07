#!/usr/bin/env python3
"""
Verifier for set_event_privacy task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_event_privacy(traj, env_info, task_info):
    """
    Verifies if the agent correctly set the event privacy and availability.
    """
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_privacy = metadata.get('expected_privacy', 'confidential')
    expected_show_as = metadata.get('expected_show_as', 'free')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Score Calculation
    score = 0
    max_score = 100
    feedback_parts = []
    
    if not result.get("event_found"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target event 'Investor Update Preparation' could not be found in the database."
        }

    # CRITERION 1: Check Privacy Setting (40 pts)
    # Expected: 'confidential' (Only Internal Users)
    # 'private' is "Only me" (Partial credit possibility, but strict task says Only Internal Users)
    actual_privacy = result.get("privacy")
    if actual_privacy == expected_privacy:
        score += 40
        feedback_parts.append("Privacy correctly set to 'Only Internal Users'.")
    elif actual_privacy == "private":
        score += 10
        feedback_parts.append("Privacy set to 'Only me' (Private) instead of 'Only Internal Users'. Partial credit.")
    elif actual_privacy == "public":
        feedback_parts.append("Privacy is still set to 'Everyone' (Public).")
    else:
        feedback_parts.append(f"Privacy set to unexpected value: {actual_privacy}.")

    # CRITERION 2: Check Show As Setting (40 pts)
    actual_show_as = result.get("show_as")
    if actual_show_as == expected_show_as:
        score += 40
        feedback_parts.append("Availability correctly set to 'Free'.")
    elif actual_show_as == "busy":
        feedback_parts.append("Availability is still set to 'Busy'.")
    else:
        feedback_parts.append(f"Availability set to unexpected value: {actual_show_as}.")

    # CRITERION 3: Anti-gaming / Write Date (10 pts)
    # Did the record actually change?
    baseline_write = result.get("baseline_write_date")
    current_write = result.get("write_date")
    
    if baseline_write and current_write and baseline_write != current_write:
        score += 10
        feedback_parts.append("Event modification confirmed.")
    else:
        feedback_parts.append("No modification detected on the event record.")

    # CRITERION 4: Integrity Check (10 pts)
    # Ensure name, start, stop weren't messed up
    integrity_ok = True
    if result.get("name") != result.get("baseline_name"):
        integrity_ok = False
        feedback_parts.append("Warning: Event name was changed.")
    if result.get("start") != result.get("baseline_start"):
        integrity_ok = False
        feedback_parts.append("Warning: Event start time was changed.")
    
    if integrity_ok:
        score += 10
        feedback_parts.append("Event integrity maintained (name/time unchanged).")

    # 3. Final Determination
    passed = score >= 80  # Requires correct fields + integrity or anti-gaming check
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }