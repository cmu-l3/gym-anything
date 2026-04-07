#!/usr/bin/env python3
"""
Verifier for change_app_interface_language task.

Verification Strategy:
1. Programmatic Checks:
   - App is running
   - User actually interacted (screenshots differ, duration > 0)
2. VLM Trajectory Verification:
   - Did agent navigate menus? (Hamburger -> Settings)
   - Did agent find Language settings?
   - Did agent select 'Deutsch'?
3. VLM Final State Verification:
   - Does the final screen show German text (Einstellungen, Karte, etc.)?
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_change_app_interface_language(traj, env_info, task_info):
    """
    Verifies that the Sygic GPS interface language was changed to German.
    """
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # Temp file handling
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    
    score = 0
    feedback_parts = []
    
    try:
        # Copy result JSON
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
            
        # Copy final screenshot for local VLM (though VLM utils often use trajectory directly)
        # We fetch it here just to confirm existence
        copy_from_env("/sdcard/task_final.png", temp_screenshot.name)
        
    except Exception as e:
        logger.error(f"Failed to retrieve task data: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve verification data from device: {str(e)}"
        }
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_screenshot.name):
            os.unlink(temp_screenshot.name)

    # 2. Basic Programmatic Checks (20 points)
    if result_data.get("app_was_running", False):
        score += 10
    else:
        feedback_parts.append("App was not running at end of task.")

    if result_data.get("screenshots_differ", False):
        score += 10
    else:
        feedback_parts.append("No visible changes detected (Do Nothing).")
        # If no changes, immediate fail
        return {"passed": False, "score": score, "feedback": "Did nothing: Initial and final screens are identical."}

    if result_data.get("task_duration_sec", 0) < 5:
        feedback_parts.append("Task completed suspiciously fast.")

    # 3. VLM Trajectory Verification (40 points)
    # Check if the agent actually performed the workflow
    frames = sample_trajectory_frames(traj, n=6)
    
    traj_prompt = """
    Analyze these screenshots of an agent using Sygic GPS Navigation.
    The goal is to change the interface language to German.
    
    Look for these steps:
    1. Opening the main menu (hamburger icon) or Settings.
    2. Navigating to "Language", "Regional", or "View" settings.
    3. Scrolling through a list of languages.
    4. Selecting "Deutsch" or "German".
    
    Did the agent perform these actions?
    Respond with JSON: {"performed_workflow": boolean, "confidence": float, "details": "string"}
    """
    
    traj_response = query_vlm(images=frames, prompt=traj_prompt)
    traj_result = traj_response.get("parsed", {})
    
    if traj_result.get("performed_workflow", False):
        score += 40
        feedback_parts.append("Trajectory confirms correct workflow.")
    else:
        feedback_parts.append(f"Workflow unclear: {traj_result.get('details', 'No details')}")

    # 4. VLM Final State Verification (40 points)
    # Check if the final result is actually German
    final_frame = get_final_screenshot(traj)
    
    final_prompt = """
    Analyze this final screenshot of Sygic GPS Navigation.
    The interface language should be German (Deutsch).
    
    Check for German keywords:
    - "Einstellungen" (instead of Settings)
    - "Karte" (instead of Map)
    - "Suchen" (instead of Search)
    - "Navigation"
    - "Anmelden" (Sign in)
    - "Hilfe" (Help)
    
    Is the interface primarily in German?
    Respond with JSON: {"is_german": boolean, "english_text_visible": boolean, "details": "string"}
    """
    
    final_response = query_vlm(images=[final_frame], prompt=final_prompt)
    final_result = final_response.get("parsed", {})
    
    is_german = final_result.get("is_german", False)
    
    if is_german:
        score += 40
        feedback_parts.append("Final screen confirms German interface.")
    else:
        feedback_parts.append(f"Final screen does not look like German: {final_result.get('details')}")

    # Final scoring logic
    passed = score >= 70 and is_german
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }