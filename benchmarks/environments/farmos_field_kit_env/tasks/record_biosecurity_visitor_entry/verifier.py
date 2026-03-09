#!/usr/bin/env python3
"""
Verifier for record_biosecurity_visitor_entry task.

Verification Strategy:
1. VLM Analysis of Trajectory:
   - Since the specific details (Driver name, Notes) are hidden inside the log details
     and might not be visible on the final list screen, we MUST analyze the agent's
     trajectory (actions) to verify they typed the correct information.
   - We check frames where the keyboard is visible or text is being entered.

2. VLM Analysis of Final State:
   - Verifies the log was saved and appears in the list with the correct title.
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_biosecurity_log(traj, env_info, task_info):
    """
    Verifies the biosecurity log creation task using VLM trajectory analysis.
    """
    # 1. Setup and access artifacts
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    # Download result JSON from device to check timestamps/files
    local_result_json = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/sdcard/task_result.json", local_result_json)
        with open(local_result_json, 'r') as f:
            device_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve device results: {str(e)}"}
    finally:
        if os.path.exists(local_result_json):
            os.remove(local_result_json)

    # 2. Prepare VLM Inputs
    # We need to see the data entry steps (middle of trajectory) and the result (end)
    trajectory_frames = sample_trajectory_frames(traj, n=8)
    final_frame = get_final_screenshot(traj)
    
    if not trajectory_frames:
        return {"passed": False, "score": 0, "feedback": "No trajectory frames available"}

    # 3. Construct VLM Prompt
    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('log_title', "Biosecurity Log")
    expected_driver = metadata.get('driver_name', "M. Chen")
    expected_vehicle = metadata.get('vehicle_id', "TRK-882")
    
    prompt = f"""
    You are evaluating an agent performing a data entry task in the farmOS Field Kit app.
    
    TASK GOAL: Create a log with the following details:
    - Title: "{expected_title}"
    - Notes containing: "{expected_driver}", "{expected_vehicle}", "Undercarriage spray"
    - Quantity: 1 visit
    
    Analyze the provided screenshots (ordered chronologically) and the final screen.
    
    Check for these specific criteria:
    1. [Data Entry] Did the agent type "{expected_driver}" or "{expected_vehicle}" into a notes field?
    2. [Data Entry] Did the agent enter the quantity "1" and unit "visit"?
    3. [Log Type] Did the agent select "Activity" as the log type?
    4. [Completion] Does the final screen show a list containing "{expected_title}"?
    
    Respond in JSON format:
    {{
        "driver_info_entered": true/false,
        "quantity_entered": true/false,
        "log_type_correct": true/false,
        "log_saved_successfully": true/false,
        "confidence": "high/medium/low",
        "reasoning": "Explain what you saw in the frames"
    }}
    """

    # 4. Query VLM
    images = trajectory_frames + [final_frame]
    response = query_vlm(prompt=prompt, images=images)

    if not response.get('success'):
        return {"passed": False, "score": 0, "feedback": f"VLM verification failed: {response.get('error')}"}

    result = response.get('parsed', {})
    logger.info(f"VLM Analysis: {result}")

    # 5. Scoring
    score = 0
    feedback_items = []

    # Criterion 1: Driver/Vehicle Info (30 pts)
    if result.get('driver_info_entered'):
        score += 30
        feedback_items.append("Correctly entered driver/vehicle details.")
    else:
        feedback_items.append("Failed to verify driver/vehicle details in notes.")

    # Criterion 2: Quantity (20 pts)
    if result.get('quantity_entered'):
        score += 20
        feedback_items.append("Correctly entered quantity.")
    else:
        feedback_items.append("Quantity entry missed or incorrect.")

    # Criterion 3: Log Type (20 pts)
    if result.get('log_type_correct'):
        score += 20
        feedback_items.append("Log type set to Activity.")
    else:
        feedback_items.append("Incorrect log type.")

    # Criterion 4: Saved & Visible (30 pts)
    if result.get('log_saved_successfully'):
        score += 30
        feedback_items.append("Log saved and visible in list.")
    else:
        feedback_items.append("Log not found in final list.")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_items),
        "details": result
    }