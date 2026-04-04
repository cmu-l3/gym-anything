#!/usr/bin/env python3
"""
Verifier for GCompris Projectile Physics (Gravity) task.
Uses VLM trajectory analysis to verify the feedback loop (fire -> adjust -> success).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_projectile_physics_gravity(traj, env_info, task_info):
    """
    Verify that the agent navigated to the Gravity activity, interacted with controls,
    and achieved the success state.
    """
    # 1. Setup and basic checks
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read export result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if not result_data.get("app_running", False):
        return {"passed": False, "score": 0, "feedback": "GCompris was not running at the end of the task."}

    # 2. VLM Trajectory Analysis
    # We need to see the progression: Navigation -> Interaction -> Success
    frames = sample_trajectory_frames(traj, n=6)
    final_screenshot = get_final_screenshot(traj)
    
    # Combined analysis prompt
    prompt = """
    You are analyzing a screen recording of a user playing the 'Gravity' physics game in GCompris.
    The user must:
    1. Navigate to the Science category and open 'Gravity' (icon usually has a planet/cannon).
    2. Fire a projectile.
    3. Adjust Angle and/or Speed sliders/controls.
    4. Hit the target object.

    Review the provided frames and determine:
    1. Did the user open the Gravity activity? (Look for a cannon/launcher on the left and a target planet/object on the right).
    2. Did the user adjust the controls? (Look for sliders changing positions or numbers changing between frames).
    3. Did the projectile fire? (Look for a projectile in flight or an arc trace).
    4. Was the target hit? (Look for a 'Success', 'Bravo', 'Good', or a star/explosion animation).

    Return JSON:
    {
        "activity_opened": true/false,
        "controls_adjusted": true/false,
        "projectile_fired": true/false,
        "target_hit": true/false,
        "reasoning": "description of what you saw"
    }
    """

    # We use the sequence of frames + final screenshot for context
    # Note: If frames list is empty, handle gracefully
    if not frames and not final_screenshot:
        return {"passed": False, "score": 0, "feedback": "No screenshots available for verification."}
        
    images_to_analyze = frames + ([final_screenshot] if final_screenshot else [])
    
    vlm_response = query_vlm(
        images=images_to_analyze,
        prompt=prompt
    )

    if not vlm_response.get("success"):
        return {"passed": False, "score": 0, "feedback": "VLM verification failed to run."}

    analysis = vlm_response.get("parsed", {})
    
    # 3. Scoring Calculation
    score = 0
    feedback_items = []

    # Criterion 1: Activity Opened (20 pts)
    if analysis.get("activity_opened"):
        score += 20
        feedback_items.append("Gravity activity accessed.")
    else:
        feedback_items.append("Gravity activity NOT found.")

    # Criterion 2: Interaction (Firing) (20 pts)
    if analysis.get("projectile_fired"):
        score += 20
        feedback_items.append("Projectile fired.")
    else:
        feedback_items.append("No evidence of firing.")

    # Criterion 3: Parameter Adjustment (20 pts)
    # This prevents 'lucky shot' or 'do nothing' gaming if the default happens to hit (unlikely but possible)
    if analysis.get("controls_adjusted"):
        score += 20
        feedback_items.append("Parameters adjusted.")
    else:
        feedback_items.append("Parameters NOT adjusted.")

    # Criterion 4: Success State (40 pts)
    if analysis.get("target_hit"):
        score += 40
        feedback_items.append("Target successfully hit.")
    else:
        feedback_items.append("Target NOT hit.")

    # Final Pass Logic
    # Must hit target AND have opened the activity (sanity check)
    passed = (score >= 80) and analysis.get("target_hit")

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_items),
        "details": analysis
    }