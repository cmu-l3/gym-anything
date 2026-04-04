#!/usr/bin/env python3
"""
Verifier for Redraw Grid Pattern task in GCompris.

Verification Strategy:
1. File Evidence (30%): Checks if agent saved the requested screenshot and if it was created during the task.
2. VLM Trajectory (70%): Analyzes frames to verify:
   - Navigation to the correct activity.
   - Active interaction (grid filling).
   - Successful completion (pattern matched).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_redraw_grid_pattern(traj, env_info, task_info):
    """
    Verify the agent completed the Redraw Grid Pattern activity.
    """
    # 1. Setup and load result JSON from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # =========================================================
    # CRITERION 1: File Evidence (30 points)
    # =========================================================
    evidence_exists = result.get("evidence_file_exists", False)
    created_during = result.get("file_created_during_task", False)
    file_size = result.get("evidence_file_size", 0)
    
    if evidence_exists:
        if file_size > 10000: # >10KB
            score += 10
            feedback_parts.append("Screenshot file exists.")
            
            if created_during:
                score += 20
                feedback_parts.append("Screenshot created during task (timestamp valid).")
            else:
                feedback_parts.append("Screenshot timestamp invalid (pre-dates task).")
        else:
            feedback_parts.append("Screenshot file too small (likely empty).")
    else:
        feedback_parts.append("No screenshot file saved by agent.")

    # =========================================================
    # CRITERION 2: VLM Trajectory Verification (70 points)
    # =========================================================
    # We sample frames to see the progression
    frames = sample_trajectory_frames(traj, n=6)
    
    prompt = """
    You are verifying a user interacting with the GCompris educational software "Redraw the given image" activity.
    
    The activity interface looks like:
    - A split screen with two grids.
    - Left grid: Displays a colored pattern (the target).
    - Right grid: Initially blank or partially filled, user clicks cells to color them.
    - Goal: Make the right grid match the left grid.
    
    Analyze the sequence of images and determine:
    1. ACTIVITY_OPEN: Is the "Redraw" activity (two grids) visible in any frame?
    2. INTERACTION: Is there evidence of the user filling the grid? (e.g., right grid changes state/color between frames)?
    3. COMPLETION: Is the pattern successfully matched? Look for:
       - The two grids looking identical.
       - A "Great" / "Excellent" animation or bonus image (flower, sun, tux).
       - An arrow appearing to go to the next level.
    
    Respond in JSON format:
    {
        "activity_open": true/false,
        "interaction_observed": true/false,
        "completion_success": true/false,
        "reasoning": "brief explanation"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=prompt)
    
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        # Scoring based on VLM findings
        if parsed.get("activity_open"):
            score += 15
            feedback_parts.append("VLM: Activity opened successfully.")
            
            if parsed.get("interaction_observed"):
                score += 25
                feedback_parts.append("VLM: Grid interaction observed.")
                
                if parsed.get("completion_success"):
                    score += 30
                    feedback_parts.append("VLM: Level completion verified.")
                else:
                    feedback_parts.append("VLM: Completion not observed (grids do not match).")
            else:
                feedback_parts.append("VLM: No interaction with grid observed.")
        else:
            feedback_parts.append("VLM: Correct activity not found in screenshots.")
    else:
        feedback_parts.append("VLM verification failed (API error).")

    # =========================================================
    # Final Decision
    # =========================================================
    # Pass threshold: 60 points
    # This requires at least: File Evidence (30) + Activity Open (15) + Interaction (25) = 70
    # OR: Activity Open (15) + Interaction (25) + Completion (30) = 70 (even if file save failed)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }