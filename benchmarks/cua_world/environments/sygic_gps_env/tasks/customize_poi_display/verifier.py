#!/usr/bin/env python3
"""
Verifier for customize_poi_display task.

Verification Strategy:
1. File Check: confirmation screenshot exists (5 pts).
2. VLM Trajectory Check: Agent navigated to Settings > POI (20 pts).
3. VLM State Check: 
   - 'Petrol/Gas Station' is Enabled (25 pts)
   - 'Parking' is Enabled (25 pts)
   - Other categories are Disabled (25 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_poi_display(traj, env_info, task_info):
    """
    Verifies that the agent configured the map POI display settings correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    task_dir_android = "/sdcard/tasks/customize_poi_display"
    result_json_path = f"{task_dir_android}/task_result.json"
    confirmation_img_path = f"{task_dir_android}/poi_config_done.png"
    final_state_img_path = f"{task_dir_android}/final_state.png"

    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. Fetch JSON Result
    # ================================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_json_path, temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # ================================================================
    # 2. Check Confirmation Screenshot (5 pts)
    # ================================================================
    if task_result.get("confirmation_screenshot_exists", False):
        score += 5
        feedback_parts.append("Confirmation screenshot saved.")
    else:
        feedback_parts.append("Confirmation screenshot missing.")

    # ================================================================
    # 3. VLM Verification (Trajectory & Final State)
    # ================================================================
    
    # Prepare images for VLM
    # We use trajectory frames to verify the workflow (finding settings)
    # We use the final screenshot (or confirmation screenshot) to verify settings
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    # If the agent saved a specific confirmation screenshot, try to fetch it to use as the "final" evidence
    # as it might show the settings better than the actual final frame if the agent navigated away.
    evidence_image = final_screen
    try:
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        copy_from_env(confirmation_img_path, temp_img.name)
        # In a real scenario we would load this image. For this template, 
        # we rely on the framework's trajectory, but note that the specific file exists.
        if os.path.getsize(temp_img.name) > 100:
             # If we could load this into the VLM pipeline we would. 
             # Assuming standard gym-anything VLM uses framework captured frames.
             pass 
        os.unlink(temp_img.name)
    except:
        pass

    prompt = """
    You are verifying an Android navigation task. The user was asked to:
    1. Open Sygic GPS Settings.
    2. Go to Map/POI settings.
    3. Enable ONLY 'Petrol/Gas Station' and 'Parking'.
    4. Disable ALL other POI categories.

    Analyze the provided screenshots (trajectory and final state).
    
    Determine:
    1. Did the user reach the POI/Map settings screen?
    2. Looking at the toggle switches in the final or latest relevant screenshot:
       - Is 'Petrol/Gas Station' (or similar) toggled ON?
       - Is 'Parking' (or similar) toggled ON?
       - Are other visible categories (Restaurant, Hotel, Shopping, etc.) toggled OFF?
    
    Note: Sygic toggles usually show color (Blue/Green) for ON and Grey for OFF.

    Return JSON:
    {
        "settings_reached": boolean,
        "gas_enabled": boolean,
        "parking_enabled": boolean,
        "others_disabled": boolean,
        "confidence": "high/medium/low",
        "reasoning": "string"
    }
    """

    vlm_response = query_vlm(images=frames + [evidence_image], prompt=prompt)
    
    if not vlm_response.get("success"):
        return {
            "passed": False, 
            "score": score, 
            "feedback": f"VLM verification failed: {vlm_response.get('error')}"
        }

    analysis = vlm_response.get("parsed", {})
    logger.info(f"VLM Analysis: {analysis}")

    # Score based on VLM analysis
    if analysis.get("settings_reached"):
        score += 20
        feedback_parts.append("Navigated to POI settings.")
    else:
        feedback_parts.append("Did not find POI settings.")

    if analysis.get("gas_enabled"):
        score += 25
        feedback_parts.append("Gas stations enabled.")
    else:
        feedback_parts.append("Gas stations NOT enabled.")

    if analysis.get("parking_enabled"):
        score += 25
        feedback_parts.append("Parking enabled.")
    else:
        feedback_parts.append("Parking NOT enabled.")

    if analysis.get("others_disabled"):
        score += 25
        feedback_parts.append("Other categories disabled.")
    else:
        feedback_parts.append("Other categories left enabled.")

    # Final logic
    passed = score >= 75  # Requires at least settings found + 2/3 configuration criteria correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts),
        "details": analysis
    }