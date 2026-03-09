#!/usr/bin/env python3
"""
Verifier for the GCompris Fifteen Puzzle task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fifteen_puzzle(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Found the Fifteen Puzzle activity.
    2. Actively played it (tiles moved).
    3. Solved it (sequential order or success animation).
    4. Saved a screenshot of the result.
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. File Verification (30 points)
    # Check if the agent saved the requested screenshot
    file_exists = result.get("output_file_exists", False)
    file_created_fresh = result.get("output_file_created_during_task", False)
    file_size = result.get("output_file_size", 0)

    if file_exists and file_created_fresh and file_size > 5000:
        score += 30
        feedback_parts.append("Screenshot file created successfully.")
    elif file_exists:
        score += 10
        feedback_parts.append("Screenshot file exists but timestamp or size checks failed.")
    else:
        feedback_parts.append("No screenshot file found at expected path.")

    # 3. VLM Verification - Trajectory Analysis (35 points)
    # Did they find the game and play it?
    frames = sample_trajectory_frames(traj, n=4)
    
    traj_prompt = """
    You are analyzing screenshots of a user using GCompris educational software.
    Look for the 'Fifteen Puzzle' (sliding tile puzzle) activity.
    
    Check for:
    1. ACTIVITY_FOUND: Is the Fifteen Puzzle activity visible (a grid of numbered tiles)?
    2. INTERACTION: Do the tile positions change between frames, indicating the user is sliding them?
    
    Return JSON:
    {
        "activity_found": true/false,
        "tiles_moved": true/false,
        "reasoning": "..."
    }
    """
    
    traj_analysis = query_vlm(images=frames, prompt=traj_prompt)
    
    activity_found = False
    tiles_moved = False
    
    if traj_analysis and traj_analysis.get("success"):
        parsed = traj_analysis.get("parsed", {})
        if parsed.get("activity_found"):
            score += 15
            activity_found = True
            feedback_parts.append("Fifteen Puzzle activity found.")
        if parsed.get("tiles_moved"):
            score += 20
            tiles_moved = True
            feedback_parts.append("Evidence of gameplay (tiles moving).")
    
    # 4. VLM Verification - Final State (35 points)
    # Did they actually solve it?
    # We check the final system screenshot OR the agent's saved screenshot (if valid)
    final_sys_screenshot = get_final_screenshot(traj)
    
    final_prompt = """
    You are verifying if a 'Fifteen Puzzle' (sliding tiles) is solved.
    
    A SOLVED state means:
    - The tiles are arranged in numerical order: 1, 2, 3, 4 (first row), 5, 6, 7, 8 (second), etc.
    - OR there is a clear "Congratulations", "Good Job", or success animation (often a flower or Tux appearing).
    
    Return JSON:
    {
        "is_solved": true/false,
        "success_animation_visible": true/false,
        "reasoning": "..."
    }
    """
    
    final_analysis = query_vlm(image=final_sys_screenshot, prompt=final_prompt)
    
    puzzle_solved = False
    if final_analysis and final_analysis.get("success"):
        parsed = final_analysis.get("parsed", {})
        if parsed.get("is_solved") or parsed.get("success_animation_visible"):
            score += 35
            puzzle_solved = True
            feedback_parts.append("Puzzle confirmed solved (ordered tiles or success animation).")
        else:
            feedback_parts.append("Puzzle does not appear solved in final state.")

    # 5. Final Calculation
    # Pass if score >= 60 AND (Puzzle Solved OR (File Created AND Tiles Moved))
    # We want to be lenient if they solved it but forgot the file, or created the file and played but VLM missed the exact 'solved' frame.
    # But ideally, they must solve it.
    
    passed = score >= 60 and (puzzle_solved or (file_exists and tiles_moved))
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }