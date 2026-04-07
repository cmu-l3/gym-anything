#!/usr/bin/env python3
"""
Verifier for enable_parking_reminder task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_parking_reminder(traj, env_info, task_info):
    """
    Verifies that the parking reminder feature was enabled.
    
    Strategy:
    1. Programmatic: Check if shared_prefs changed and now contain a "true" value for parking.
    2. VLM: Check trajectory to confirm the agent navigated settings and toggled the specific switch.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    score = 0
    feedback_log = []
    
    # =========================================================
    # 1. Programmatic Verification (Config Files)
    # =========================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/tasks/enable_parking_reminder/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Criterion: App was left running (5 pts)
    if result_data.get("app_running", False):
        score += 5
        feedback_log.append("App is running.")

    # Criterion: Preferences were modified (10 pts)
    # This prevents "do nothing" agents or just clicking randomly without saving
    if result_data.get("prefs_changed", False):
        score += 10
        feedback_log.append("Settings configuration was modified.")
    else:
        feedback_log.append("No changes detected in settings configuration.")

    # Criterion: Parking feature appears enabled in config (35 pts)
    # The shell script greps for "park" + "true/1"
    if result_data.get("parking_feature_enabled", False):
        score += 35
        feedback_log.append("Configuration file indicates parking reminder is ENABLED.")
    else:
        feedback_log.append("Configuration file does NOT show parking reminder enabled.")

    # =========================================================
    # 2. VLM Verification (Visual Evidence)
    # =========================================================
    # We use VLM to verify the agent actually found the correct menu
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    # Prompt for VLM analysis
    prompt = """
    You are verifying an agent's task to 'Enable Parking Place Reminder' in a GPS app.
    Review the screenshots and determine:
    1. Did the agent navigate into the Settings menu?
    2. Did the agent find a section related to 'Navigation', 'Notifications', or 'Parking'?
    3. Is there a toggle specifically for 'Parking place reminder' or 'Save parking'?
    4. Does the FINAL state show this toggle in the ON (usually colored/right) position?
    
    Answer JSON:
    {
      "settings_accessed": boolean,
      "parking_toggle_visible": boolean,
      "toggle_is_on": boolean,
      "confidence": "low|medium|high"
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_screen], prompt=prompt)
    vlm_data = vlm_result.get("parsed", {})
    
    # Score VLM findings
    if vlm_data.get("settings_accessed", False):
        score += 15
        feedback_log.append("Visuals confirm Settings menu was accessed.")
        
    if vlm_data.get("parking_toggle_visible", False):
        score += 15
        feedback_log.append("Visuals confirm the parking toggle was located.")
        
    if vlm_data.get("toggle_is_on", False):
        score += 20
        feedback_log.append("Visuals confirm the toggle is in the ON position.")
    else:
        feedback_log.append("Visuals do NOT clearly show the toggle in ON position.")

    # =========================================================
    # Final Assessment
    # =========================================================
    
    # Must have either config confirmation OR strong visual confirmation of "ON" state
    # AND must have done some work (score > 0)
    config_success = result_data.get("parking_feature_enabled", False)
    visual_success = vlm_data.get("toggle_is_on", False)
    
    passed = (score >= 60) and (config_success or visual_success)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_log)
    }