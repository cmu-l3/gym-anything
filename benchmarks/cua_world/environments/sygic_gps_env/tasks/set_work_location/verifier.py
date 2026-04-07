#!/usr/bin/env python3
"""
Verifier for set_work_location task (Sygic GPS).

Verification Strategy:
1. Programmatic: Check if app preferences were modified and contain target string/coords.
2. Visual (VLM): Analyze trajectory to confirm "Work" location flow was used.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_work_location(traj, env_info, task_info):
    """
    Verifies that the Work location was set to World Trade Center.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []

    # =======================================================
    # 1. Programmatic Verification (App State) - 40 Points
    # =======================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result json: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    files_modified = result_data.get("app_files_modified", 0)
    found_text = result_data.get("data_found_text", False)
    found_coords = result_data.get("data_found_coords", False)

    # Criterion: App state changed (Anti-gaming)
    if files_modified > 0:
        score += 10
        feedback_parts.append("App configuration updated.")
    else:
        feedback_parts.append("No changes detected in app settings.")

    # Criterion: Target location data found
    if found_text:
        score += 30
        feedback_parts.append("Found 'World Trade Center' in app data.")
    elif found_coords:
        score += 20
        feedback_parts.append("Found target coordinates in app data.")
    else:
        feedback_parts.append("Target location data NOT found in app storage.")

    # =======================================================
    # 2. VLM Verification (Trajectory) - 60 Points
    # =======================================================
    # We examine the trajectory to ensure the user actually set the 'Work' location
    # and didn't just search for it or set a random favorite.
    
    frames = sample_trajectory_frames(traj, n=6)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying an Android navigation task. 
    The goal is to set the 'Work' location to 'World Trade Center'.
    
    Review the screenshots and answer:
    1. Did the user open a menu showing 'Work' or 'Set Work' option?
    2. Did the user search for 'World Trade Center'?
    3. Did the user select a result in New York?
    4. In the final state, does the 'Work' icon appear set (colored/active) or is 'World Trade Center' visible as the Work address?
    
    Respond in JSON:
    {
        "menu_accessed": boolean,
        "search_performed": boolean,
        "correct_selection": boolean,
        "final_state_verified": boolean,
        "explanation": "string"
    }
    """
    
    try:
        vlm_response = query_vlm(
            images=frames + [final_screen],
            prompt=vlm_prompt
        )
        vlm_data = vlm_response.get("parsed", {})
        
        if vlm_data.get("menu_accessed"):
            score += 10
        if vlm_data.get("search_performed"):
            score += 10
        if vlm_data.get("correct_selection"):
            score += 20
        if vlm_data.get("final_state_verified"):
            score += 20
            
        feedback_parts.append(f"VLM Analysis: {vlm_data.get('explanation', 'No explanation')}")
        
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        feedback_parts.append("VLM verification failed to execute.")

    # =======================================================
    # Final Scoring
    # =======================================================
    
    # Pass threshold: 60 points.
    # Must have at least some programmatic evidence OR strong visual confirmation.
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }