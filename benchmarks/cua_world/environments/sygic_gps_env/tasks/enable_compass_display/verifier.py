#!/usr/bin/env python3
"""
Verifier for enable_compass_display task.

Verifies that:
1. Agent navigated to settings
2. Agent interacted with Compass/North Indicator settings
3. Compass is visible on the final map view
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_compass_display(traj, env_info, task_info):
    """
    Verify the compass display task using VLM analysis of trajectory and final state.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Fetch artifacts
    temp_dir = tempfile.mkdtemp()
    try:
        # Fetch JSON result
        local_result_json = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/sdcard/task_result.json", local_result_json)
            with open(local_result_json, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            logger.warning(f"Could not load task_result.json: {e}")
            task_result = {}

        # We primarily rely on framework-captured trajectory, but final screenshot from script is good backup
        pass
    finally:
        # Cleanup is handled by tempfile usually, but we keep it simple here
        pass

    # 2. VLM Verification
    # We construct a prompt that asks the VLM to verify specific milestones
    
    frames = sample_trajectory_frames(traj, n=6)
    final_frame = get_final_screenshot(traj)
    
    if not final_frame:
        return {"passed": False, "score": 0, "feedback": "No screenshots available for verification"}

    prompt = """
    You are verifying an Android navigation task. 
    The goal was: "Configure Sygic GPS to ALWAYS display the compass/north indicator on the map."

    Review the screenshots (chronological order) and the final screen.
    
    Check for these specific events:
    1. Did the user open the 'Settings' menu?
    2. Did the user enter 'Map' or 'Display' settings?
    3. Did the user toggle 'Compass' or 'North indicator' to 'Always' or 'On'?
    4. CRITICAL: In the FINAL screenshot, is the compass icon (usually a small red/white arrow or circle) visible on the map?
       Note: The map should look static (not being dragged). If the compass is visible, the task is successful.
    
    Output JSON:
    {
        "settings_opened": boolean,
        "compass_setting_changed": boolean,
        "compass_visible_in_final": boolean,
        "confidence": 0-100,
        "reasoning": "string"
    }
    """

    # Query VLM
    vlm_response = query_vlm(
        images=frames + [final_frame],
        prompt=prompt
    )
    
    if not vlm_response.get("success"):
        return {"passed": False, "score": 0, "feedback": "VLM verification failed to run"}

    result_data = vlm_response.get("parsed", {})
    
    # 3. Scoring
    score = 0
    feedback_parts = []
    
    # Criterion 1: Process (Settings navigation)
    if result_data.get("settings_opened"):
        score += 20
        feedback_parts.append("Navigated to settings")
    
    # Criterion 2: Action (Setting changed)
    if result_data.get("compass_setting_changed"):
        score += 30
        feedback_parts.append("Changed compass setting")
        
    # Criterion 3: Result (Compass visible)
    compass_visible = result_data.get("compass_visible_in_final", False)
    if compass_visible:
        score += 50
        feedback_parts.append("Compass visible on final map")
    else:
        feedback_parts.append("Compass NOT visible on final map")

    # Final Pass/Fail logic
    # Must have at least attempted the setting change OR achieved the visual result
    passed = score >= 80 and compass_visible
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result_data
    }