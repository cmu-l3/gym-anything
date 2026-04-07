#!/usr/bin/env python3
"""
Verifier for view_afd_info task (Avare Aviation GPS).

Verification Strategy:
1. Programmatic: Check if app is running and if target text (KSQL/San Carlos) is in UI dump.
2. VLM Trajectory: Verify the workflow (Search -> Select -> A/FD Tab).
3. VLM Final State: Verify the final screen shows the Facility Directory for KSQL.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_view_afd_info(traj, env_info, task_info):
    """
    Verify that the agent searched for KSQL and opened the A/FD tab.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    remote_result_path = "/sdcard/tasks/view_afd_info/result.json"
    
    # 1. Fetch result.json from device
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(remote_result_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy or parse result.json: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results from device"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Basic Signals
    app_running = result_data.get("app_running", False)
    text_found_xml = result_data.get("target_text_found_in_xml", False)

    score = 0
    feedback_parts = []

    # Criterion 1: App must be running (10 pts)
    if app_running:
        score += 10
        feedback_parts.append("App is running")
    else:
        feedback_parts.append("App was closed or crashed")

    # Criterion 2: Target text in XML dump (20 pts)
    # This is a strong signal but not sufficient (could be just on the map)
    if text_found_xml:
        score += 20
        feedback_parts.append("Target airport text found in UI")
    else:
        feedback_parts.append("Target airport text NOT found in UI")

    # 3. VLM Verification (Trajectory & Final State)
    # We need to verify the *workflow* and the *specific tab*.
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if not final_screen:
        return {"passed": False, "score": score, "feedback": "No screenshots available for verification"}
    
    # Combine frames for VLM context
    # We use a single comprehensive prompt to grade the interaction
    
    vlm_prompt = """
    You are verifying an agent operating an aviation GPS app (Avare).
    The goal is: Search for airport 'KSQL' (San Carlos) and view its 'A/FD' (Airport/Facility Directory) page.

    Review the sequence of images and the final screen.
    
    Check for these specific steps:
    1. Did the agent open a 'Find' or 'Search' interface?
    2. Did the agent type 'KSQL' or select San Carlos airport?
    3. Is the FINAL screen displaying the 'A/FD' tab? (Look for text 'A/FD' at the top or bottom tabs, or specific directory data like frequencies/elevation).
    4. Does the final screen show info for 'San Carlos' or 'KSQL'?
    
    Reject if:
    - The agent is still on the Map view (showing a moving map).
    - The agent is on the 'Plan' tab or 'Plates' tab instead of A/FD.
    - The airport selected is NOT KSQL.

    Respond in JSON format:
    {
        "search_performed": boolean,
        "ksql_selected": boolean,
        "afd_tab_active": boolean,
        "correct_airport_data_visible": boolean,
        "confidence": "low|medium|high",
        "reasoning": "string"
    }
    """
    
    vlm_images = frames + [final_screen]
    vlm_result = query_vlm(images=vlm_images, prompt=vlm_prompt)
    
    vlm_data = vlm_result.get("parsed", {})
    if not vlm_result.get("success"):
        feedback_parts.append(f"VLM verification failed: {vlm_result.get('error')}")
    else:
        # Score VLM components
        if vlm_data.get("search_performed", False):
            score += 15
            feedback_parts.append("Search workflow detected")
            
        if vlm_data.get("ksql_selected", False):
            score += 15
            feedback_parts.append("KSQL selected")
            
        if vlm_data.get("afd_tab_active", False):
            score += 20
            feedback_parts.append("A/FD Tab is active")
            
        if vlm_data.get("correct_airport_data_visible", False):
            score += 20
            feedback_parts.append("Correct Facility Data visible")
            
        feedback_parts.append(f"VLM Reasoning: {vlm_data.get('reasoning', 'None')}")

    # Final logic
    # Pass threshold: 70 points
    # Must have A/FD tab active AND correct data visible to pass
    
    critical_success = vlm_data.get("afd_tab_active", False) and vlm_data.get("correct_airport_data_visible", False)
    passed = (score >= 70) and critical_success

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }