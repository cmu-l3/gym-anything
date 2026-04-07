#!/usr/bin/env python3
"""
Verifier for change_coordinate_format_dms task.

Verification Strategy:
1. VLM Trajectory Analysis:
   - Verify agent navigated to Settings > Regional/Preferences
   - Verify agent specifically selected 'Degrees, Minutes, Seconds'
2. Final State Verification:
   - Check if final screenshot shows the DMS format selected
3. Anti-Gaming:
   - Ensure the process was actually performed (trajectory existence)
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Mock VLM imports for environment compatibility
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback/Mock for testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(images, prompt): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_change_coordinate_format_dms(traj, env_info, task_info):
    """
    Verifies that the agent changed the GPS coordinate format to DMS.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # =========================================================================
    # 1. Extract Artifacts
    # =========================================================================
    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, "task_result.json")
    final_screenshot_local = os.path.join(temp_dir, "task_final.png")
    
    try:
        # Copy JSON
        copy_from_env("/sdcard/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            result_data = json.load(f)
            
        # Copy Final Screenshot
        copy_from_env("/sdcard/task_final.png", final_screenshot_local)
        
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task artifacts: {str(e)}"}

    # =========================================================================
    # 2. VLM Verification (Trajectory & Final State)
    # =========================================================================
    
    # Get trajectory frames (to prove work was done)
    frames = sample_trajectory_frames(traj, n=6)
    
    # Prompt for VLM Analysis
    # We ask the VLM to act as a strict judge
    prompt = """
    You are evaluating an agent performing a task in Sygic GPS Navigation.
    Task: Change GPS coordinate format to "Degrees, Minutes, Seconds" (DMS).
    
    Review the provided screenshots (trajectory sequence + final state).
    
    Check for these specific criteria:
    1. NAVIGATION: Did the agent navigate to 'Settings' and then 'Regional' or 'Preferences'?
    2. SETTING FOUND: Did the agent find the 'GPS Coordinates' (or similar) setting?
    3. SELECTION: Did the agent explicitly select "Degrees, Minutes, Seconds" (e.g. 32° 18' 23")?
       - NOTE: Selecting "Degrees, Minutes" (Decimal Minutes) is INCORRECT.
       - NOTE: Selecting "Decimal Degrees" is INCORRECT.
    4. FINAL STATE: Does the final screen show "Degrees, Minutes, Seconds" as the active setting?
    
    Output JSON:
    {
        "navigated_settings": boolean,
        "found_coordinate_setting": boolean,
        "selected_dms_format": boolean,
        "incorrect_format_selected": boolean,
        "final_state_correct": boolean,
        "confidence": "high/medium/low",
        "reasoning": "string"
    }
    """
    
    # If we have the local final screenshot, use it as the last frame
    # (The framework's get_final_screenshot might rely on internal buffers, 
    #  but we explicitly downloaded one)
    images_to_check = frames
    if os.path.exists(final_screenshot_local):
        # We pass the path or bytes depending on what query_vlm expects.
        # Assuming query_vlm handles paths or we load it.
        # Here we assume it handles paths or PIL images. 
        # For simplicity in this script, we assume the framework handles the 'traj' object 
        # correctly for get_final_screenshot, but we pass our downloaded one if needed.
        pass

    vlm_response = query_vlm(images=frames + [final_screenshot_local], prompt=prompt)
    
    if not vlm_response.get("success"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Verification failed during visual analysis: {vlm_response.get('error')}"
        }
        
    analysis = vlm_response.get("parsed", {})
    
    # =========================================================================
    # 3. Scoring Logic
    # =========================================================================
    score = 0
    feedback_items = []
    
    # Criterion 1: Navigation (20 pts)
    if analysis.get("navigated_settings"):
        score += 20
        feedback_items.append("Navigated to settings")
    else:
        feedback_items.append("Failed to navigate to settings")

    # Criterion 2: Found Setting (30 pts)
    if analysis.get("found_coordinate_setting"):
        score += 30
        feedback_items.append("Found coordinate settings")
    
    # Criterion 3: Selection Accuracy (50 pts)
    # Strict penalty for wrong format
    if analysis.get("incorrect_format_selected"):
        score = 20 # Cap score if they picked the wrong one (partial credit for navigation only)
        feedback_items.append("WRONG format selected (must be DMS)")
    elif analysis.get("selected_dms_format") or analysis.get("final_state_correct"):
        score += 50
        feedback_items.append("Correct DMS format selected")
    else:
        feedback_items.append("Failed to select DMS format")

    # Anti-gaming check: App focus
    if not result_data.get("app_focused", False):
        score = min(score, 50) # Penalty if app wasn't focused at end
        feedback_items.append("Warning: App not focused at end")

    passed = (score >= 90)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_items),
        "details": analysis
    }