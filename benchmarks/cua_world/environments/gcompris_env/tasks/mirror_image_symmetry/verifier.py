#!/usr/bin/env python3
"""
Verifier for Mirror Image Symmetry task.

Verification Strategy:
1. File Check: Did the agent save a screenshot to ~/mirror_solved.png? (20 pts)
2. VLM Trajectory Analysis:
   - Did the agent navigate to the correct 'Reflections' activity? (20 pts)
   - Is there evidence of interaction (grid cells changing)? (20 pts)
   - Is the puzzle solved (symmetric pattern or success message)? (40 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mirror_image_symmetry(traj, env_info, task_info):
    """
    Verify the Mirror Image task using file checks and VLM trajectory analysis.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # 1. READ EXPORTED RESULT (File Checks)
    # ================================================================
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

    score = 0
    feedback_parts = []
    
    # Check 1: Output file existence (20 pts)
    # The agent was asked to take a screenshot and save it.
    if result_data.get('output_exists', False) and result_data.get('file_created_during_task', False):
        score += 20
        feedback_parts.append("Screenshot file created successfully.")
    elif result_data.get('output_exists', False):
        score += 10
        feedback_parts.append("Screenshot file exists but timestamp is suspicious.")
    else:
        feedback_parts.append("No output screenshot found at ~/mirror_solved.png.")

    # ================================================================
    # 2. VLM TRAJECTORY ANALYSIS (80 pts)
    # ================================================================
    # We sample frames to see the progression: Menu -> Activity -> Interaction -> Success
    frames = sample_trajectory_frames(traj, n=5)
    
    if not frames:
        return {"passed": False, "score": score, "feedback": "No trajectory frames available for VLM analysis."}

    prompt = """
    You are verifying an agent's performance in the GCompris educational software.
    The task is to find the 'Reflections' (Mirror Image) activity and solve a symmetry puzzle.
    
    Look at the sequence of screenshots and answer the following:

    1. ACTIVITY_FOUND: Do you see the 'Reflections' or 'Mirror Image' activity? It typically looks like a grid divided by a line, with a pattern on one side and empty grid cells on the other.
    2. INTERACTION: Do you see evidence of the user 'painting' or clicking grid cells on the empty side? (e.g., cells changing color across frames).
    3. PUZZLE_SOLVED: In the later frames, is the pattern symmetrical? Does the right side mirror the left side? Or do you see a success indicator (smiley face, 'OK' button, fireworks, flower)?
    
    Return JSON:
    {
        "activity_found": true/false,
        "interaction_visible": true/false,
        "puzzle_solved": true/false,
        "reasoning": "Explain what you see"
    }
    """

    vlm_result = query_vlm(images=frames, prompt=prompt)
    
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        # Scoring based on VLM
        if parsed.get("activity_found", False):
            score += 20
            feedback_parts.append("VLM confirmed correct activity navigation.")
        else:
            feedback_parts.append("VLM did not see the Mirror Image activity.")

        if parsed.get("interaction_visible", False):
            score += 20
            feedback_parts.append("VLM confirmed interaction with the grid.")
        
        if parsed.get("puzzle_solved", False):
            score += 40
            feedback_parts.append("VLM confirmed the puzzle was solved (symmetry/success state).")
        else:
            feedback_parts.append("VLM did not see a solved puzzle state.")
            
        logger.info(f"VLM Reasoning: {parsed.get('reasoning')}")
    else:
        feedback_parts.append(f"VLM verification failed: {vlm_result.get('error')}")

    # ================================================================
    # FINAL SCORE AGGREGATION
    # ================================================================
    
    # Pass threshold: 80 points (Must generally solve the puzzle)
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }