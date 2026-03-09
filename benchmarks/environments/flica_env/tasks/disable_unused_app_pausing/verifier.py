#!/usr/bin/env python3
"""
Verifier for disable_unused_app_pausing task.

Verifies that the agent successfully disabled the "Pause app activity if unused" 
(auto-revoke permissions) setting for Flight Crew View.
"""

import json
import os
import tempfile
import logging
import sys

# Add parent directory for shared utilities if needed
# sys.path.insert(0, str(Path(__file__).parent.parent))
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_disable_unused_app_pausing(traj, env_info, task_info):
    """
    Verify the task completion.
    
    Success Criteria:
    1. Programmatic: autoRevokePermissionsMode must be 2 (MODE_IGNORED).
    2. VLM: Trajectory should show interaction with App Info / Settings.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON from the environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse task result: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # --- Criteria 1: System State Check (70 points) ---
    # mode 2 = MODE_IGNORED (Success: Revocation is disabled)
    # mode 0 or 1 = Default/Allowed (Failure: Revocation is enabled)
    final_mode = result.get("auto_revoke_mode", -1)
    
    score = 0
    feedback_parts = []
    
    if final_mode == 2:
        score += 70
        feedback_parts.append("✅ Setting successfully disabled (System confirmed)")
        passed_programmatic = True
    else:
        feedback_parts.append(f"❌ Setting is still enabled (Mode: {final_mode})")
        passed_programmatic = False

    # --- Criteria 2: VLM Trajectory Verification (30 points) ---
    # Ensure they actually used the UI and didn't just find a shell loophole 
    # (though unlikely in this restricted env, good for robustness)
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if frames:
        vlm_prompt = """
        Review these screenshots of an Android agent.
        The goal is to disable 'Pause app activity if unused' for the app 'Flight Crew View'.
        
        Check for:
        1. Did the agent navigate to 'App Info' or 'Settings'?
        2. Is the 'Flight Crew View' app page visible?
        3. Do you see a toggle for 'Pause app activity if unused' (or 'Remove permissions') being switched off?
        
        Respond with JSON: {"settings_visited": bool, "toggle_interaction": bool}
        """
        
        # This is a placeholder for actual VLM call - in production this calls the model
        # For this implementation, we rely on the helper provided by the framework
        try:
            vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
            vlm_data = vlm_result.get("parsed", {})
            
            if vlm_data.get("settings_visited"):
                score += 15
                feedback_parts.append("✅ Navigation to Settings confirmed")
            else:
                feedback_parts.append("⚠️ Settings navigation not clearly visible")
                
            if vlm_data.get("toggle_interaction"):
                score += 15
                feedback_parts.append("✅ Toggle interaction confirmed")
            else:
                feedback_parts.append("⚠️ Toggle interaction not clearly visible")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            # Fallback points if programmatic pass and settings activity detected
            if passed_programmatic and result.get("settings_activity_detected"):
                score += 30
                feedback_parts.append("✅ Settings activity detected (fallback verification)")

    # Final logic
    passed = passed_programmatic and score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }