#!/usr/bin/env python3
"""
Verifier for Avare set_track_up_orientation task.

Criteria:
1. Preferences file must be modified during the task (Anti-gaming).
2. 'TrackUp' preference must be set to 'true' in the XML.
3. VLM verification of the final state (Map View vs Preferences Menu).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_track_up_orientation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Extract programmatic data
    prefs_modified = result_data.get("file_modified_during_task", False)
    track_up_enabled = result_data.get("track_up_enabled", False)
    app_running = result_data.get("app_running", False)

    score = 0
    feedback = []

    # 2. Programmatic Scoring
    if app_running:
        score += 10
        feedback.append("App is running.")
    else:
        feedback.append("App was closed (penalty).")

    if prefs_modified:
        score += 20
        feedback.append("Preferences were modified.")
    else:
        feedback.append("Preferences file was NOT modified (did you save?).")

    if track_up_enabled:
        score += 40
        feedback.append("Track Up setting detected in preferences file.")
    else:
        feedback.append("Track Up setting NOT found in preferences.")

    # 3. VLM Verification
    # We want to verify the user returned to the map, or at least navigated correctly.
    final_screenshot = get_final_screenshot(traj)
    
    vlm_score = 0
    if final_screenshot:
        prompt = """
        You are verifying a task in the Avare Aviation GPS app.
        The goal was to enable 'Track Up' mode and return to the map.
        
        Look at the screenshot:
        1. Is the main map view visible? (Look for a map, compass rose, aviation chart features)
        2. OR is the Preferences screen visible showing 'Track Up' checked?
        
        Note: If you see the Map, it is generally good. If you see the Preferences screen with 'Track Up' checked, that is also partial success, though the user should have returned to the map.
        
        Return JSON:
        {
            "is_map_view": boolean,
            "is_prefs_view": boolean,
            "track_up_checked": boolean (only if on prefs view),
            "feedback": "string explaining what you see"
        }
        """
        
        try:
            vlm_response = query_vlm(prompt=prompt, image=final_screenshot)
            
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                is_map = parsed.get("is_map_view", False)
                is_prefs = parsed.get("is_prefs_view", False)
                checked = parsed.get("track_up_checked", False)
                
                if is_map:
                    vlm_score = 30
                    feedback.append("VLM: Returned to Map view successfully.")
                elif is_prefs and checked:
                    vlm_score = 20
                    feedback.append("VLM: Stayed on Preferences screen, but setting appears checked.")
                elif is_prefs:
                    vlm_score = 10
                    feedback.append("VLM: On Preferences screen, but couldn't confirm checkmark.")
                else:
                    feedback.append("VLM: Unrecognized screen.")
            else:
                feedback.append(f"VLM Error: {vlm_response.get('error')}")
        except Exception as e:
            feedback.append(f"VLM Exception: {str(e)}")
            
    score += vlm_score

    # 4. Final Verdict
    # Must have technically enabled the setting (programmatic) AND got a decent score
    passed = track_up_enabled and score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }