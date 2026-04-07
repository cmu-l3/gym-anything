#!/usr/bin/env python3
"""
Verifier for disable_auto_device_addition task.

Scoring Strategy:
1. Behavioral Check (60 pts): A simulated log from a new IP (192.168.254.254) 
   MUST NOT result in a new device being added to the database.
   - This proves the "Auto Add" feature is effectively disabled.
2. VLM Check (40 pts): Verify via screenshot/trajectory that the agent 
   navigated to Settings and interacted with the correct toggle.

Pass Threshold: 60 points (Behavioral check is mandatory).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_disable_auto_device_addition(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Analyze Behavioral Result (The Gold Standard)
    # logic: If behavior_check_passed is true, it means the device was NOT found in DB.
    behavior_passed = result.get("behavioral_check_passed", False)
    device_found = result.get("device_found_in_db", True)

    if behavior_passed:
        score += 60
        feedback.append("Success: New device was ignored (Auto-Add is disabled).")
    else:
        feedback.append("Failure: New device was automatically added to the database.")
        if device_found:
             feedback.append("(Evidence: Test IP found in Resources table)")

    # 3. VLM / Trajectory Verification (Supplementary)
    # We check if they at least visited the settings page, useful for partial credit 
    # or confirming *how* they did it.
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    
    vlm_prompt = """
    You are verifying if an agent disabled "Automatic Device Addition" in a SIEM interface.
    Look at the sequence of screens.
    
    1. Did the agent navigate to a "Settings", "Admin", or "Device Management" page?
    2. Did you see a toggle/checkbox related to "Auto Add", "Automatically add discovered devices", or "Manage new devices automatically"?
    3. Did the agent interact with it (uncheck/disable)?
    
    Return JSON:
    {
        "settings_visited": true/false,
        "setting_found": true/false,
        "interaction_observed": true/false
    }
    """
    
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('settings_visited'):
                score += 10
                feedback.append("VLM: Settings page visited.")
            
            if parsed.get('interaction_observed'):
                score += 30
                feedback.append("VLM: Observed interaction with auto-add setting.")
                
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Fallback: If behavioral passed, we assume they did it right.
        if behavior_passed:
            score += 40
            feedback.append("VLM skipped, but behavioral test passed.")

    # Cap score
    score = min(100, score)
    
    # Pass logic: Must pass behavioral check
    passed = behavior_passed and score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }