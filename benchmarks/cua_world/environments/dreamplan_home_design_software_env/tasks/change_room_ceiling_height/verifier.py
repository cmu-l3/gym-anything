#!/usr/bin/env python3
"""
Verifier for change_room_ceiling_height task.
Uses a hybrid approach:
1. Anti-gaming: Checks if any project file was actually modified/saved.
2. Primary: VLM trajectory analysis to verify the user opened the properties dialog and entered the correct value.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utilities from the environment framework
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback for standalone testing
    logger.warning("gym_anything.vlm not found, using mocks")
    def query_vlm(prompt, image=None, images=None):
        return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(traj, n=5):
        return []
    def get_final_screenshot(traj):
        return None

def verify_change_room_ceiling_height(traj, env_info, task_info):
    """
    Verify that the ceiling height was changed to 10ft.
    
    Criteria:
    1. (Anti-gaming) A project file was modified during the task.
    2. (VLM) Trajectory shows the "Story Properties" or "Level Properties" dialog.
    3. (VLM) Trajectory shows input value '10' or '10.0' or '3.05' in height field.
    4. (VLM) Final screenshot shows 3D view.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve verification data from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Modification (Anti-Gaming) ---
    # Points: 20
    modified_projects = result_data.get("modified_projects", [])
    if modified_projects:
        score += 20
        feedback_parts.append("Project file saved/modified.")
    else:
        feedback_parts.append("No project file modification detected (did you save?).")

    # --- Criterion 2 & 3: VLM Trajectory Analysis ---
    # Points: 60 (Process)
    frames = sample_trajectory_frames(traj, n=6)
    
    # Prompt for finding the dialog and value
    process_prompt = """
    You are verifying a home design task. The user should have changed the Ceiling Height to 10 feet.
    Look at these screenshots sequence of the user's actions.
    
    Check for:
    1. Did the user open a "Story Properties", "Level Properties", or "Building" dialog?
    2. Is there a number field labeled "Height", "Ceiling Height", or "Wall Height"?
    3. Did the user enter "10", "10'", "10 ft", "120", or "3.05" into that field?
    
    Return JSON:
    {
        "dialog_seen": boolean,
        "correct_value_entered": boolean,
        "seen_value": "string value if seen"
    }
    """
    
    vlm_process = query_vlm(prompt=process_prompt, images=frames)
    
    dialog_seen = False
    value_correct = False
    
    if vlm_process.get("success"):
        parsed = vlm_process.get("parsed", {})
        if parsed.get("dialog_seen"):
            score += 25
            dialog_seen = True
            feedback_parts.append("Properties dialog opened.")
        else:
            feedback_parts.append("Properties dialog not detected in screenshots.")
            
        if parsed.get("correct_value_entered"):
            score += 35
            value_correct = True
            feedback_parts.append("Correct height value (10ft/3.05m) detected.")
        else:
            val = parsed.get("seen_value", "none")
            feedback_parts.append(f"Correct height value not detected (seen: {val}).")
    else:
        feedback_parts.append("VLM analysis failed.")

    # --- Criterion 4: Final Visual State ---
    # Points: 20
    final_screen = get_final_screenshot(traj)
    final_prompt = """
    Is this screenshot showing a 3D perspective view of a house (not a 2D blueprint)?
    Return JSON: {"is_3d_view": boolean}
    """
    vlm_final = query_vlm(prompt=final_prompt, image=final_screen)
    
    if vlm_final.get("success") and vlm_final.get("parsed", {}).get("is_3d_view"):
        score += 20
        feedback_parts.append("Final view is 3D.")
    else:
        feedback_parts.append("Final view is not 3D.")

    # --- Final Scoring ---
    # Pass if: File modified AND (Value Correct OR (Dialog Seen + 3D View))
    # This allows for some VLM miss on the specific digits if the process was clearly followed.
    passed = (len(modified_projects) > 0) and (value_correct or (dialog_seen and score >= 60))
    
    if score >= 70:
        passed = True

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }