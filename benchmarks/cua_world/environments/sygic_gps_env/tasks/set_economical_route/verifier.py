#!/usr/bin/env python3
"""
Verifier for set_economical_route task.

Strategy:
1. Verify via internal preferences (Config persistence) - Primary
2. Verify via VLM (Visual confirmation) - Secondary
3. Verify via App State (App running) - Hygiene
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_economical_route(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: App Running (10 pts)
    if result.get("app_was_running", False):
        score += 10
        feedback_parts.append("App was running")
    else:
        feedback_parts.append("App was NOT running")

    # Criterion 2: Preferences Modified (20 pts)
    # This prevents "do nothing" if the setting was already coincidentally correct
    if result.get("prefs_modified_during_task", False):
        score += 20
        feedback_parts.append("Settings modified")
    else:
        feedback_parts.append("Settings NOT modified")

    # Criterion 3: Config Verification (30 pts)
    if result.get("found_economical_setting", False):
        score += 30
        feedback_parts.append("Config confirms Economical mode")
    else:
        feedback_parts.append("Config does NOT show Economical mode")

    # Criterion 4: VLM Verification (40 pts)
    # We use VLM to verify the UI state, as config files might be cryptic or inaccessible
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if frames and final_screen:
        prompt = """
        You are verifying a task in Sygic GPS Navigation.
        The user wants to set the Route Computing method to "Economical".
        
        Look at the screenshot sequence.
        1. Did the user navigate to Settings?
        2. Did the user open Route Planning / Route Settings?
        3. Is "Economical" (or Eco) selected as the route computing method in the final state?
        
        Respond with JSON:
        {
            "settings_opened": true/false,
            "economical_selected": true/false,
            "confidence": "high/medium/low"
        }
        """
        
        # Use final screenshot and a few frames for context
        vlm_response = query_vlm(images=frames + [final_screen], prompt=prompt)
        
        if vlm_response.get("success"):
            parsed = vlm_response.get("parsed", {})
            if parsed.get("settings_opened"):
                score += 10
            if parsed.get("economical_selected"):
                score += 30
                feedback_parts.append("Visual confirmation: Economical selected")
            else:
                feedback_parts.append("Visual verification failed")
        else:
            feedback_parts.append("VLM verification error")
            # Fallback points if config was strong
            if result.get("found_economical_setting", False):
                score += 20 

    # Final scoring
    passed = score >= 65 and (result.get("found_economical_setting", False) or "Economical selected" in str(feedback_parts))
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }