#!/usr/bin/env python3
"""
Verifier for configure_drop_compliance task in Vicidial.

This task checks if the agent correctly configured 5 specific FCC compliance settings
for the 'TESTCAMP' campaign.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_drop_compliance(traj, env_info, task_info):
    """
    Verify compliance settings were applied to the campaign.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_drop = metadata.get('expected_drop_seconds', '5')
    expected_exten = metadata.get('expected_extension', '8300')
    expected_lockout = metadata.get('expected_lockout', '3')
    expected_audio = metadata.get('expected_audio_field', 'DISABLED')
    expected_entity = metadata.get('expected_message_entity', 'Acme Insurance Services')
    expected_phone = metadata.get('expected_message_phone', '1-800-555-0199')

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    max_score = 100
    feedback_parts = []

    # 1. Verify Drop Call Seconds (15 pts)
    actual_drop = str(result.get('drop_call_seconds', '0'))
    if actual_drop == expected_drop:
        score += 15
        feedback_parts.append("Drop Seconds Correct")
    else:
        feedback_parts.append(f"Drop Seconds Incorrect ({actual_drop} vs {expected_drop})")

    # 2. Verify Safe Harbor Extension (15 pts)
    actual_exten = str(result.get('safe_harbor_exten', ''))
    if actual_exten == expected_exten:
        score += 15
        feedback_parts.append("Extension Correct")
    else:
        feedback_parts.append(f"Extension Incorrect ({actual_exten})")

    # 3. Verify Message Content (30 pts split)
    actual_message = result.get('safe_harbor_message', '')
    
    # Entity Name Check (15 pts)
    if expected_entity.lower() in actual_message.lower():
        score += 15
        feedback_parts.append("Entity Name in Message")
    else:
        feedback_parts.append("Entity Name MISSING in Message")

    # Phone Number Check (15 pts)
    if expected_phone in actual_message:
        score += 15
        feedback_parts.append("Callback Number in Message")
    else:
        feedback_parts.append("Callback Number MISSING in Message")

    # 4. Verify Drop Lockout Time (15 pts)
    actual_lockout = str(result.get('drop_lockout_time', '0'))
    if actual_lockout == expected_lockout:
        score += 15
        feedback_parts.append("Lockout Time Correct")
    else:
        feedback_parts.append(f"Lockout Time Incorrect ({actual_lockout})")

    # 5. Verify Safe Harbor Audio Field (10 pts)
    actual_audio = str(result.get('safe_harbor_audio_field', ''))
    if actual_audio == expected_audio:
        score += 10
        feedback_parts.append("Audio Field Correct")
    else:
        feedback_parts.append(f"Audio Field Incorrect ({actual_audio})")
        
    # Anti-gaming check: Values must have changed from initial state
    values_changed = result.get('values_changed_from_initial', False)
    if not values_changed and score > 0:
        score = 0
        feedback_parts = ["ANTI-GAMING: Values did not change from initial state (Task was to modify them)"]

    # VLM Trajectory Check (Optional but good practice)
    # Ideally we check if the agent visited the campaign screen
    # For this task, strict value matching is usually sufficient evidence of work
    # as the probability of guessing the specific message string is zero.

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }