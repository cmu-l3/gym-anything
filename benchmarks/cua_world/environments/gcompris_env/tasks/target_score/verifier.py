#!/usr/bin/env python3
"""
Verifier for GCompris Target Activity task.

Verification Strategy:
1. VLM Trajectory Analysis (Primary):
   - Sample frames from the trajectory.
   - Verify the "Target" activity (bullseye) was visible.
   - Verify darts were thrown (dots on target).
   - Verify score input interaction.
   - Verify level progression (different target values or level indicators).
2. State Checks (Secondary):
   - Verify GCompris files were modified (implies activity progress).
   - Verify final screenshot exists.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying an agent playing the 'Target' math game in GCompris.
The game involves throwing darts at a bullseye target with number rings, summing the score, and entering it.

Review the sequence of screenshots and answer the following in JSON format:

1. "activity_found": (bool) Is the Target activity visible (bullseye with concentric rings) in at least one frame?
2. "gameplay_detected": (bool) Do you see darts (dots/arrows) on the target OR numbers being entered into an input box?
3. "progression_observed": (bool) Does the game state change significantly between frames? Look for:
   - Different target values on the rings (e.g., rings showing 1,2,3 then later 5,10,20).
   - A 'Level' indicator changing.
   - A 'Congratulations' or 'Correct' animation.
4. "returned_to_menu": (bool) Does the final frame show the main menu (activity selection icons) or a different activity?

Respond with:
{
  "activity_found": true/false,
  "gameplay_detected": true/false,
  "progression_observed": true/false,
  "returned_to_menu": true/false,
  "reasoning": "brief explanation"
}
"""

def verify_target_score(traj, env_info, task_info):
    """
    Verify the agent completed the Target math activity.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load exported result
    task_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution data"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. VLM Analysis of Trajectory
    # We sample 5 frames to capture the workflow: Menu -> Level 1 -> Level 2 -> Level 3 -> Menu
    frames = sample_trajectory_frames(traj, n=5)
    
    if not frames:
        return {"passed": False, "score": 0, "feedback": "No trajectory frames available for verification"}

    vlm_response = query_vlm(images=frames, prompt=VLM_PROMPT)
    
    if not vlm_response.get('success'):
        return {"passed": False, "score": 0, "feedback": f"VLM verification failed: {vlm_response.get('error')}"}

    vlm_data = vlm_response.get('parsed', {})
    
    # 3. Scoring
    score = 0
    feedback_parts = []

    # Criterion A: Found the activity (20 pts)
    if vlm_data.get('activity_found'):
        score += 20
        feedback_parts.append("Found Target activity.")
    else:
        feedback_parts.append("Failed to find Target activity.")

    # Criterion B: Gameplay interaction (30 pts)
    if vlm_data.get('gameplay_detected'):
        score += 30
        feedback_parts.append("Played the game (threw darts/calculated score).")
    else:
        feedback_parts.append("No gameplay interaction detected.")

    # Criterion C: Progression/Multiple Levels (30 pts)
    # This implies they completed at least one level to get to a new configuration
    if vlm_data.get('progression_observed'):
        score += 30
        feedback_parts.append("Progressed through multiple game states/levels.")
    else:
        feedback_parts.append("No level progression observed (stuck on one screen).")

    # Criterion D: App State/Files (10 pts)
    # If GCompris updated internal DB/config files, it confirms valid interaction
    if task_result.get('files_modified'):
        score += 10
        feedback_parts.append("Application data was updated (valid interaction).")
    
    # Criterion E: Return to Menu / Clean Exit (10 pts)
    if vlm_data.get('returned_to_menu'):
        score += 10
        feedback_parts.append("Returned to main menu.")

    # Pass Threshold
    # Must find activity AND show gameplay (50 pts minimum)
    passed = (score >= 50 and 
              vlm_data.get('activity_found') and 
              (vlm_data.get('gameplay_detected') or vlm_data.get('progression_observed')))

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts),
        "details": {
            "vlm_analysis": vlm_data,
            "task_result": task_result
        }
    }