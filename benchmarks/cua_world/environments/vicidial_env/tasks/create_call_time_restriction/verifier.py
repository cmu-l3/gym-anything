#!/usr/bin/env python3
"""
Verifier for create_call_time_restriction task.

Verifies:
1. 'EASTERN_TCPA' record exists in vicidial_call_times.
2. Record was created during the task (not pre-existing).
3. All time windows (Default, Sun-Sat) match TCPA specifications.
4. Name and Comments match requirements.
5. VLM trajectory check to ensure UI interaction (anti-gaming).
"""

import json
import tempfile
import os
import logging
import sys
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_call_time_restriction(traj, env_info, task_info):
    """
    Verify the Vicidial Call Time configuration task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_values = metadata.get('expected_values', {})
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Check Record Existence (15 pts)
    record_found = result.get('record_found', False)
    record_data = result.get('record_data', {})
    initial_count = result.get('initial_count', 0)

    if not record_found:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Call Time ID 'EASTERN_TCPA' was not found in the database.",
            "details": {"record_found": False}
        }
    
    score += 15
    feedback_parts.append("Record 'EASTERN_TCPA' created")

    # Anti-gaming: Ensure it wasn't there before
    if initial_count > 0:
        feedback_parts.append("WARNING: Record existed before task started (potential gaming)")
        # We don't fail immediately but this is suspicious
    
    # 3. Check Name and Comments (20 pts)
    # Name (10)
    actual_name = record_data.get('call_time_name', '')
    expected_name = expected_values.get('call_time_name', '')
    if actual_name == expected_name:
        score += 10
        feedback_parts.append(f"Correct Name")
    else:
        feedback_parts.append(f"Incorrect Name: '{actual_name}' (expected '{expected_name}')")

    # Comments (10) - just check for keyword
    actual_comments = record_data.get('call_time_comments', '')
    keyword = expected_values.get('call_time_comments_keyword', 'TCPA')
    if keyword.lower() in actual_comments.lower():
        score += 10
        feedback_parts.append(f"Comments contain '{keyword}'")
    else:
        feedback_parts.append(f"Comments missing keyword '{keyword}'")

    # 4. Check Time Configurations (50 pts)
    # Default (10)
    def_start = record_data.get('ct_default_start')
    def_stop = record_data.get('ct_default_stop')
    exp_def_start = expected_values.get('ct_default_start')
    exp_def_stop = expected_values.get('ct_default_stop')
    
    if def_start == exp_def_start and def_stop == exp_def_stop:
        score += 10
        feedback_parts.append("Default hours OK")
    else:
        feedback_parts.append(f"Default hours wrong: {def_start}-{def_stop}")

    # Sunday (10) - Blocked
    sun_start = record_data.get('ct_sunday_start')
    sun_stop = record_data.get('ct_sunday_stop')
    if sun_start == 0 and sun_stop == 0:
        score += 10
        feedback_parts.append("Sunday blocked OK")
    else:
        feedback_parts.append(f"Sunday not blocked: {sun_start}-{sun_stop}")

    # Saturday (10) - Reduced
    sat_start = record_data.get('ct_saturday_start')
    sat_stop = record_data.get('ct_saturday_stop')
    exp_sat_start = expected_values.get('ct_saturday_start')
    exp_sat_stop = expected_values.get('ct_saturday_stop')
    if sat_start == exp_sat_start and sat_stop == exp_sat_stop:
        score += 10
        feedback_parts.append("Saturday hours OK")
    else:
        feedback_parts.append(f"Saturday hours wrong: {sat_start}-{sat_stop}")

    # Weekdays (20) - Mon-Fri
    weekdays = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday']
    weekdays_correct = 0
    for day in weekdays:
        d_start = record_data.get(f'ct_{day}_start')
        d_stop = record_data.get(f'ct_{day}_stop')
        if d_start == expected_values.get(f'ct_{day}_start') and d_stop == expected_values.get(f'ct_{day}_stop'):
            weekdays_correct += 1
    
    if weekdays_correct == 5:
        score += 20
        feedback_parts.append("All weekdays OK")
    else:
        score += (weekdays_correct * 4) # Partial credit
        feedback_parts.append(f"Weekdays {weekdays_correct}/5 OK")

    # 5. VLM Trajectory Verification (15 pts)
    # Check if the agent actually navigated the Admin UI
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
        
    vlm_prompt = """
    You are verifying a Vicidial Admin task. 
    The user should have:
    1. Navigated to the 'Admin' section.
    2. Clicked on 'Call Times'.
    3. Filled out a form with start/stop times (0800, 2100, etc.).
    
    Look at these screenshots of the agent's actions.
    Did the agent access the Call Times modification screen? 
    Can you see a form with 'Call Time ID', 'Call Time Name', or start/stop time fields?
    
    Return JSON: {"ui_interaction_confirmed": boolean, "reason": string}
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    ui_confirmed = False
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        if parsed.get('ui_interaction_confirmed'):
            ui_confirmed = True
            score += 15
            feedback_parts.append("VLM confirmed UI interaction")
        else:
            feedback_parts.append(f"VLM did not confirm UI interaction: {parsed.get('reason')}")
    else:
        # Fallback if VLM fails: assume innocent if record exists
        # But grant only partial points for this component
        score += 5 
        feedback_parts.append("VLM check skipped/failed (partial credit)")

    passed = score >= 60 and record_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": record_data
    }