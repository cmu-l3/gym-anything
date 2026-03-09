#!/usr/bin/env python3
"""
Verifier for change_global_property task.

Verifies that:
1. The OpenMRS global property 'default_locale' is now 'fr'.
2. The change happened via the UI during the task window (anti-gaming via timestamps).
3. VLM trajectory analysis confirms UI interaction.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_change_global_property(traj, env_info, task_info):
    """
    Verify the global property change.
    """
    # 1. Setup Env Access
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env not available"}

    # 2. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract Data
    api_value = result.get('final_api_value', '')
    db_value = result.get('final_db_value', '')
    db_ts = int(result.get('final_db_ts', 0))
    initial_ts = int(result.get('initial_property_ts', 0))
    task_start = int(result.get('task_start_time', 0))
    expected_value = task_info.get('metadata', {}).get('expected_value', 'fr')

    score = 0
    feedback = []
    
    # ------------------------------------------------------------------
    # Programmatic Verification (70 points max)
    # ------------------------------------------------------------------

    # Criterion 1: Value Match (API) - 20 pts
    if api_value == expected_value:
        score += 20
        feedback.append(f"✅ API reports correct value: '{api_value}'")
    else:
        feedback.append(f"❌ API reports incorrect value: '{api_value}' (Expected: '{expected_value}')")

    # Criterion 2: Value Match (DB) - 20 pts
    if db_value == expected_value:
        score += 20
        feedback.append(f"✅ Database reports correct value: '{db_value}'")
    else:
        feedback.append(f"❌ Database reports incorrect value: '{db_value}'")

    # Criterion 3: Anti-Gaming (Timestamp Check) - 30 pts
    # The record must have been updated AFTER the task started AND later than the initial state
    # Allow 1-2 seconds clock skew tolerance if needed, but usually not necessary on same VM
    if db_ts > initial_ts and db_ts >= task_start:
        score += 30
        feedback.append("✅ Property was modified during the task session")
    elif db_value == expected_value:
        # Value is correct but timestamp suggests it wasn't changed *now*
        # This catches "it was already correct" or "agent didn't click save" if TS didn't update
        feedback.append("⚠️ Property has correct value but was NOT modified during this session (timestamp check failed)")
        score += 5 # Minimal points for luck/pre-existing state
    else:
        feedback.append("❌ Property was not modified")

    # ------------------------------------------------------------------
    # VLM Verification (30 points max)
    # ------------------------------------------------------------------
    # We want to verify the agent actually navigated the Admin UI, 
    # rather than just using a hidden API script or similar.
    
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        
        # Analyze trajectory for Admin UI presence
        prompt = """
        Review these screenshots of a user interacting with the OpenMRS/Bahmni system.
        The user goal is: Navigate to Administration > Global Properties and change 'default_locale'.
        
        Determine the following:
        1. Did the user access the 'Administration' or 'Maintenance' section?
        2. Is a list of global properties or settings visible in any frame?
        3. Is there evidence of changing the 'default_locale' setting?
        
        Respond with JSON: {"admin_ui_seen": bool, "properties_list_seen": bool, "interaction_detected": bool}
        """
        
        try:
            vlm_resp = query_vlm(images=frames + [final_frame], prompt=prompt)
            parsed = vlm_resp.get('parsed', {})
            
            if parsed.get('admin_ui_seen'):
                vlm_score += 10
                feedback.append("✅ VLM: Admin UI visited")
            if parsed.get('properties_list_seen'):
                vlm_score += 10
                feedback.append("✅ VLM: Properties list accessed")
            if parsed.get('interaction_detected'):
                vlm_score += 10
                feedback.append("✅ VLM: Interaction detected")
                
        except Exception as e:
            feedback.append(f"⚠️ VLM check failed: {e}")
            # Fallback: if programmatic check passed fully, give partial credit for VLM
            if score >= 70: 
                vlm_score += 15
                feedback.append("✅ VLM: Skipped (Programmatic success assumed valid)")

    score += vlm_score

    # Final Pass Determination
    # Must have correct value programmatically AND meaningful VLM/Timestamp evidence
    passed = (score >= 75 and api_value == expected_value)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }