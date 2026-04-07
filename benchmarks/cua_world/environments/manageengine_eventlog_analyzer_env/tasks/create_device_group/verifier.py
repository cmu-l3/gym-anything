#!/usr/bin/env python3
"""
Verifier for create_device_group task.
Verifies that the agent created a device group in EventLog Analyzer and assigned a device to it.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_device_group(traj, env_info, task_info):
    """
    Verify create_device_group task.
    
    Criteria:
    1. Device group 'DMZ_Servers' exists (30 pts)
    2. Group has correct description (10 pts)
    3. At least one device is assigned to the group (25 pts)
    4. User provided a screenshot of the result (15 pts)
    5. Anti-gaming: Group was actually created during task (10 pts)
    6. Workflow: Agent was active (trajectory check) (10 pts)
    
    Pass Threshold: 55 points (Must have group + device assignment)
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_group_name', 'DMZ_Servers')
    expected_desc_part = "Demilitarized zone"  # Key phrase to match
    
    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # 2. Score Criteria
    
    # Criterion 1: Group Exists (30 pts)
    group_exists = result.get('group_exists', False)
    actual_name = result.get('group_name', '')
    
    if group_exists:
        if expected_name.lower() in actual_name.lower():
            score += 30
            feedback_parts.append("Device group 'DMZ_Servers' found.")
        else:
            # Group found but name mismatch? (Unlikely due to SQL query, but possible via fuzzy logic)
            score += 15
            feedback_parts.append(f"Group found but name mismatch ({actual_name}).")
    else:
        feedback_parts.append("Device group 'DMZ_Servers' NOT found.")

    # Criterion 2: Description Correct (10 pts)
    actual_desc = result.get('group_description', '')
    if group_exists and expected_desc_part.lower() in actual_desc.lower():
        score += 10
        feedback_parts.append("Group description is correct.")
    elif group_exists:
        feedback_parts.append(f"Group description mismatch (Got: '{actual_desc}').")

    # Criterion 3: Device Assigned (25 pts)
    device_assigned = result.get('device_assigned', False)
    if device_assigned:
        score += 25
        feedback_parts.append("Device successfully assigned to group.")
    else:
        feedback_parts.append("No devices found in the group.")

    # Criterion 4: Screenshot Evidence (15 pts)
    screenshot_exists = result.get('user_screenshot_exists', False)
    screenshot_fresh = result.get('user_screenshot_created_during_task', False)
    
    if screenshot_exists and screenshot_fresh:
        score += 15
        feedback_parts.append("Screenshot provided.")
    elif screenshot_exists:
        score += 5
        feedback_parts.append("Screenshot exists but timestamp is old.")
    else:
        feedback_parts.append("No screenshot provided at /tmp/device_group_result.png.")

    # Criterion 5: Anti-Gaming / Freshness (10 pts)
    is_new = result.get('is_new_group', False)
    if is_new and group_exists:
        score += 10
        feedback_parts.append("Confirmed group was created during task.")
    elif group_exists:
        feedback_parts.append("Warning: Group appeared to exist before task started.")

    # Criterion 6: Workflow/App Running (10 pts)
    # If we have a result file and any score > 0, the agent did something
    if score > 0:
        score += 10
        feedback_parts.append("Workflow activity detected.")

    # 3. Final Evaluation
    passed = score >= 55 and group_exists and device_assigned
    
    if not passed:
        if not group_exists:
            feedback_parts.append("CRITICAL: Group creation failed.")
        if not device_assigned:
            feedback_parts.append("CRITICAL: No device assigned to group.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }