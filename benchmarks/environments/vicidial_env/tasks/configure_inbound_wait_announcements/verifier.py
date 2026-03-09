#!/usr/bin/env python3
"""
Verifier for configure_inbound_wait_announcements task.
Checks if Vicidial In-Group settings match the requirements.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_inbound_wait_announcements(traj, env_info, task_info):
    """
    Verifies that the Inbound Group 'TECH_SUPPORT' has been configured correctly.
    
    Scoring Breakdown (100 pts total):
    - Calculate Hold Time (15 pts)
    - Hold Time Option (15 pts)
    - Hold Time Seconds (15 pts)
    - Hold Time Minimum (15 pts)
    - Periodic Announce File (20 pts)
    - Periodic Announce Seconds (20 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_settings', {
        "calculate_hold_time": "Y",
        "hold_time_option": "MINUTES",
        "hold_time_seconds": 120,
        "hold_time_minimum": 60,
        "periodic_announce": "queue-periodic-announce",
        "periodic_announce_seconds": 45
    })

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    actual = result.get('actual_settings', {})
    
    score = 0
    feedback_parts = []
    
    # Check 1: Calculate Hold Time (15 pts)
    if actual.get('calculate_hold_time') == expected['calculate_hold_time']:
        score += 15
    else:
        feedback_parts.append(f"Calculate Hold Time: Expected {expected['calculate_hold_time']}, got {actual.get('calculate_hold_time')}")

    # Check 2: Hold Time Option (15 pts)
    if actual.get('hold_time_option') == expected['hold_time_option']:
        score += 15
    else:
        feedback_parts.append(f"Hold Time Option: Expected {expected['hold_time_option']}, got {actual.get('hold_time_option')}")

    # Check 3: Hold Time Seconds (15 pts)
    # Allow small string/int mismatch if value is correct
    if str(actual.get('hold_time_seconds')) == str(expected['hold_time_seconds']):
        score += 15
    else:
        feedback_parts.append(f"Hold Time Seconds: Expected {expected['hold_time_seconds']}, got {actual.get('hold_time_seconds')}")

    # Check 4: Hold Time Minimum (15 pts)
    if str(actual.get('hold_time_minimum')) == str(expected['hold_time_minimum']):
        score += 15
    else:
        feedback_parts.append(f"Hold Time Minimum: Expected {expected['hold_time_minimum']}, got {actual.get('hold_time_minimum')}")

    # Check 5: Periodic Announce File (20 pts)
    if actual.get('periodic_announce') == expected['periodic_announce']:
        score += 20
    else:
        feedback_parts.append(f"Periodic Announce: Expected '{expected['periodic_announce']}', got '{actual.get('periodic_announce')}'")

    # Check 6: Periodic Announce Seconds (20 pts)
    if str(actual.get('periodic_announce_seconds')) == str(expected['periodic_announce_seconds']):
        score += 20
    else:
        feedback_parts.append(f"Periodic Frequency: Expected {expected['periodic_announce_seconds']}, got {actual.get('periodic_announce_seconds')}")

    # Secondary Verification: VLM Trajectory Check
    # Ensure agent actually navigated the UI and didn't just luck out (though hard with 6 params)
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = (
            "Does the user appear to be navigating the Vicidial Admin Interface? "
            "Look for screens titled 'Show Inbound Groups', 'Modify Inbound Group', or forms with fields like 'Hold Time' or 'Periodic Announce'. "
            "Return JSON: {\"is_vicidial_admin\": boolean, \"modifying_group\": boolean}"
        )
        vlm_res = query_vlm(prompt=vlm_prompt, images=frames)
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if not parsed.get('is_vicidial_admin'):
                feedback_parts.append("Warning: Visual verification did not confirm Vicidial Admin usage.")
                # We don't penalize score here if DB is correct, but we note it.

    passed = score >= 85  # Strict pass threshold
    
    full_feedback = "Task Complete. " + "; ".join(feedback_parts) if feedback_parts else "All settings configured correctly."

    return {
        "passed": passed,
        "score": score,
        "feedback": full_feedback
    }