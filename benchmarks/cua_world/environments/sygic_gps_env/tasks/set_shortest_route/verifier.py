#!/usr/bin/env python3
"""
Verifier for set_shortest_route task.

Strategy:
1. Programmatic: Check if internal app preferences regarding routing changed (via file diffs).
2. VLM: Check final screenshot to visually confirm "Shortest" is selected in the UI.
3. VLM: Check trajectory to ensure the agent actually navigated the settings menu (process verification).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_shortest_route(traj, env_info, task_info):
    """
    Verifies that the route calculation method was set to 'Shortest'.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Fetch Result JSON from Container
    # -----------------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Programmatic Checks (30 points)
    # -----------------------------------
    
    # Check if app is running (10 pts)
    if result_data.get("app_running", False):
        score += 10
        feedback_parts.append("App is running.")
    else:
        feedback_parts.append("App was closed.")

    # Check if settings files were modified (20 pts)
    # This detects if the agent actually changed *something* in the settings
    if result_data.get("prefs_changed", False):
        score += 20
        feedback_parts.append("Settings modified.")
        logger.info(f"Modified pref files: {result_data.get('changed_pref_files')}")
    else:
        feedback_parts.append("No internal settings changed.")

    # 3. Visual Verification (VLM) (70 points)
    # ----------------------------------------
    
    # A. Final State Verification (40 pts)
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        # Prompt checking for the specific state
        final_prompt = (
            "Review this screenshot from the Sygic GPS Navigation settings menu. "
            "1. Is the 'Route computing' or 'Route type' setting visible? "
            "2. Is the option 'Shortest' selected (e.g., radio button active, text highlighted, checkmark)? "
            "3. Is 'Fastest' NOT selected? "
            "Return JSON with keys: is_settings_screen (bool), shortest_selected (bool)."
        )
        
        vlm_final = query_vlm(
            images=[final_screenshot], 
            prompt=final_prompt
        )
        
        final_parsed = vlm_final.get("parsed", {})
        
        if final_parsed.get("shortest_selected", False):
            score += 40
            feedback_parts.append("Visual confirmation: 'Shortest' route is selected.")
        elif final_parsed.get("is_settings_screen", False):
            # partial credit for being on the right screen but wrong setting
            score += 10
            feedback_parts.append("On settings screen, but 'Shortest' not clearly selected.")
        else:
            feedback_parts.append("Final screen does not show correct settings state.")

    # B. Trajectory Verification (30 pts)
    # Ensure they navigated through the menu, not just restored a backup or magic
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        traj_prompt = (
            "Analyze these frames of a user interacting with a GPS app. "
            "Did the user: "
            "1. Open the main menu? "
            "2. Navigate into Settings? "
            "3. Select Route options? "
            "Return JSON: { 'navigated_menu': bool, 'entered_settings': bool }"
        )
        
        vlm_traj = query_vlm(images=frames, prompt=traj_prompt)
        traj_parsed = vlm_traj.get("parsed", {})
        
        if traj_parsed.get("entered_settings", False):
            score += 30
            feedback_parts.append("Trajectory confirms navigation through Settings.")
        elif traj_parsed.get("navigated_menu", False):
            score += 15
            feedback_parts.append("Trajectory shows menu access.")

    # 4. Final Scoring
    # ----------------
    passed = score >= 60 and result_data.get("app_running", False) and final_parsed.get("shortest_selected", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }