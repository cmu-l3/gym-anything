#!/usr/bin/env python3
"""
Verifier for configure_aircraft_profile task.

Verifies:
1. SharedPreferences were modified (anti-gaming).
2. Correct Fuel Burn (10) and TAS (115) values exist in prefs.
3. Agent returned to the main map screen.
4. VLM verifies the trajectory involved visiting settings.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_aircraft_profile(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON from device
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/data/local/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: Fuel Burn Value (30 pts) ---
    if result.get("found_fuel_value"):
        score += 30
        feedback.append("Fuel burn rate correctly set to 10 GPH.")
    else:
        feedback.append("Fuel burn rate NOT found or incorrect.")

    # --- Criterion 2: TAS Value (30 pts) ---
    if result.get("found_tas_value"):
        score += 30
        feedback.append("TAS correctly set to 115 kts.")
    else:
        feedback.append("TAS NOT found or incorrect.")

    # --- Criterion 3: Prefs Modified & App State (20 pts) ---
    # Anti-gaming: File must actually be written to
    if result.get("prefs_modified"):
        score += 10
        feedback.append("Preferences saved successfully.")
    else:
        feedback.append("Preferences file was not modified (did you save/exit?).")

    # App state: Should be back on map
    if result.get("on_map_screen") and result.get("app_running"):
        score += 10
        feedback.append("Returned to main map view.")
    else:
        feedback.append("Did not return to main map view.")

    # --- Criterion 4: VLM Trajectory Verification (20 pts) ---
    # Verify the agent actually visited the preferences screen
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    Review these screenshots of an agent using the Avare aviation app.
    The agent's goal is to go into 'Preferences' and change settings.
    
    1. Do you see a menu or screen titled 'Preferences', 'Settings', or a list of configuration options?
    2. Do you see any input dialogs where numbers (like 10 or 115) could be entered?
    
    Return JSON: {"preferences_visited": boolean, "input_dialog_seen": boolean}
    """
    
    try:
        vlm_response = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_response.get("parsed", {})
        
        if parsed.get("preferences_visited") or parsed.get("input_dialog_seen"):
            score += 20
            feedback.append("Visual verification confirmed preferences navigation.")
        else:
            feedback.append("Visual verification failed to see preferences screen.")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if values are correct, we assume they did it, give partial credit
        if result.get("found_fuel_value") and result.get("found_tas_value"):
             score += 10
             feedback.append("VLM skipped, partial credit based on correct values.")

    # Final Pass/Fail
    # Must have correct values (60pts) to pass
    passed = (result.get("found_fuel_value") and 
              result.get("found_tas_value") and 
              score >= 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }