#!/usr/bin/env python3
"""
Verifier for clear_app_storage task.

Verification Logic:
1. Programmatic: Check if app is still installed (Agent shouldn't uninstall).
2. Programmatic: Check UI dump for "Login/Welcome" keywords (Success) vs "Friends" keywords (Failure).
3. VLM: Check trajectory to ensure agent actually went to Settings -> Storage -> Clear Data.
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_clear_storage(traj, env_info, task_info):
    """
    Verifies that the agent cleared the app storage and reset the app.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_login_text = metadata.get('expected_login_text', ["LOG IN", "Let's", "Welcome"])
    forbidden_home_text = metadata.get('forbidden_home_text', ["Friends", "Add New Friend"])

    score = 0
    feedback_parts = []
    
    # Create temp directory for artifacts
    with tempfile.TemporaryDirectory() as temp_dir:
        local_result_json = os.path.join(temp_dir, "task_result.json")
        local_ui_xml = os.path.join(temp_dir, "final_state.xml")

        # 1. Retrieve JSON Result
        try:
            copy_from_env("/sdcard/task_result.json", local_result_json)
            with open(local_result_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}

        # 2. Retrieve UI Dump
        ui_content = ""
        try:
            copy_from_env("/sdcard/final_state.xml", local_ui_xml)
            with open(local_ui_xml, 'r', encoding='utf-8', errors='ignore') as f:
                ui_content = f.read()
        except Exception as e:
            logger.warning(f"Failed to retrieve UI XML: {e}")
            # Don't fail immediately, fallback to VLM
        
        # --- CRITERION 1: App Integrity (15 pts) ---
        if result_data.get("app_installed", False):
            score += 15
            feedback_parts.append("App is still installed (Correct)")
        else:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "FAILED: The app was uninstalled. Task required clearing storage only."
            }

        # --- CRITERION 2: UI State Verification (Programmatic) (50 pts) ---
        # We check the XML for text indicating we are back at login
        is_at_login = any(keyword in ui_content for keyword in expected_login_text)
        is_still_logged_in = any(keyword in ui_content for keyword in forbidden_home_text)
        
        if is_at_login and not is_still_logged_in:
            score += 50
            feedback_parts.append("UI confirms app was reset to login screen")
        elif is_still_logged_in:
            feedback_parts.append("UI shows logged-in content (Storage not cleared)")
        else:
            feedback_parts.append("UI state ambiguous based on text analysis")

        # --- CRITERION 3: VLM Trajectory Verification (35 pts) ---
        # Did they actually go to settings?
        frames = sample_trajectory_frames(traj, n=6)
        final_screen = get_final_screenshot(traj)
        
        vlm_prompt = """
        Analyze this sequence of Android screenshots. The user task was to clear the storage data for the app "Flight Crew View".
        
        Look for these specific steps:
        1. Opening Android Settings
        2. Navigating to "Apps" or "App info"
        3. Selecting "Flight Crew View"
        4. Tapping "Storage & cache" (or just Storage)
        5. Tapping "Clear storage" or "Clear data" (NOT just clear cache)
        6. Confirming the deletion in a dialog
        7. Re-opening the Flight Crew View app
        
        Did the user complete this workflow?
        """
        
        vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        
        vlm_passed = False
        if vlm_result.get("success"):
            # Simple heuristic: if VLM says "yes" or "completed" in reasoning
            response_text = vlm_result.get("parsed", {}).get("reasoning", "") or str(vlm_result)
            if "yes" in response_text.lower() or "completed" in response_text.lower():
                score += 35
                vlm_passed = True
                feedback_parts.append("VLM verified correct settings workflow")
            else:
                feedback_parts.append("VLM did not verify clear storage workflow")
        else:
            # Fallback if VLM fails: If programmatic check passed with high confidence, grant partial points
            if score >= 65: 
                score += 15
                feedback_parts.append("VLM unavailable, partial credit granted")

    # Final Pass/Fail determination
    # Must have app installed + (UI verification OR VLM verification)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }