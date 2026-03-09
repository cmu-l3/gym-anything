#!/usr/bin/env python3
"""
Verifier for configure_shift_enforcement task.

Verifies:
1. Shift 'SURVEY_EVE' exists with correct start time (1700) and length (0500).
2. User Group 'SURVEY' has shift enforcement set to 'ALL'.
3. User Group 'SURVEY' has 'SURVEY_EVE' in its allowed shifts list.
4. VLM verification of the workflow.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_shift_enforcement(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_shift_id = metadata.get('target_shift_id', 'SURVEY_EVE')
    expected_start = metadata.get('expected_start', '1700')
    expected_length = metadata.get('expected_length', '0500')
    expected_enforcement = metadata.get('expected_enforcement', 'ALL')

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract Data
    shift_data = result.get('shift_data', {})
    group_data = result.get('group_data', {})

    # Criterion 1: Shift Exists (20 pts)
    shift_exists = shift_data.get('exists', 0) == 1
    if shift_exists:
        score += 20
        feedback_parts.append(f"Shift {expected_shift_id} created")
    else:
        feedback_parts.append(f"Shift {expected_shift_id} NOT found")

    # Criterion 2: Correct Shift Details (20 pts)
    # Start Time
    actual_start = shift_data.get('start_time', '')
    if actual_start == expected_start:
        score += 10
    else:
        feedback_parts.append(f"Shift start {actual_start} != {expected_start}")
    
    # Length
    actual_length = shift_data.get('length', '')
    if actual_length == expected_length:
        score += 10
    else:
        feedback_parts.append(f"Shift length {actual_length} != {expected_length}")

    # Criterion 3: Group Enforcement Active (30 pts)
    actual_enforcement = group_data.get('enforcement', 'OFF')
    if actual_enforcement == expected_enforcement:
        score += 30
        feedback_parts.append("Group enforcement set to ALL")
    else:
        feedback_parts.append(f"Group enforcement is {actual_enforcement} (expected ALL)")

    # Criterion 4: Shift Assigned to Group (20 pts)
    # Vicidial stores assigned shifts as a space/pipe delimited string, e.g., " |SURVEY_EVE| "
    assigned_shifts = group_data.get('group_shifts', '')
    if expected_shift_id in assigned_shifts:
        score += 20
        feedback_parts.append("Shift assigned to group correctly")
    else:
        feedback_parts.append(f"Shift {expected_shift_id} NOT in group allowed list")

    # Criterion 5: VLM Verification (10 pts)
    # Use trajectory frames to confirm they visited both screens
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """
            Analyze these screenshots of a Vicidial Admin task.
            The user should have:
            1. Visited the 'Shifts' admin page (look for 'ADD A NEW SHIFT' or shift list).
            2. Visited the 'User Groups' admin page.
            
            Return JSON: {"visited_shifts": bool, "visited_user_groups": bool}
            """
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('visited_shifts'): vlm_score += 5
                if parsed.get('visited_user_groups'): vlm_score += 5
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
    
    score += vlm_score
    if vlm_score > 0:
        feedback_parts.append(f"VLM confirmed workflow ({vlm_score} pts)")

    # Final logic
    # Must have at least created the shift and turned on enforcement to pass
    passed = (score >= 70) and shift_exists and (actual_enforcement == expected_enforcement)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }