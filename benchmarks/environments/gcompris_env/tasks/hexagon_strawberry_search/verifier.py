#!/usr/bin/env python3
"""
Verifier for GCompris Hexagon Strawberry Search Task.

Verification Strategy:
1. File Verification: Checks if 'strawberry_found.png' exists and was created during the task.
2. VLM Verification (Trajectory): Analyzes frames to confirm:
   - Navigation to the Puzzles category.
   - Interaction with the Hexagon grid (visible colored cells).
   - Discovery of the strawberry (success state).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hexagon_strawberry_search(traj, env_info, task_info):
    """
    Verifies that the agent navigated to the Hexagon activity, searched for the strawberry
    using color clues, and captured the success state.
    """
    # 1. Setup & File Access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # Retrieve task result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract File-Based Metrics
    output_exists = result_data.get("output_exists", False)
    file_created_during = result_data.get("file_created_during_task", False)
    output_size = result_data.get("output_size_bytes", 0)
    app_running = result_data.get("app_was_running", False)

    # Basic file check feedback
    feedback = []
    score = 0
    
    # 3. VLM Verification (The Core Check)
    # We sample frames to see the workflow: Menu -> Puzzles -> Hexagon Game -> Search -> Success
    frames = sample_trajectory_frames(traj, n=6)
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        frames.append(final_screenshot)

    vlm_prompt = """
    You are verifying an agent's performance in the GCompris educational software.
    The task is to play the 'Hexagon' (Find the Strawberry) game.
    
    Look at the sequence of screenshots and answer the following questions JSON format:
    
    1. "visited_puzzles_category": Do you see the GCompris menu showing puzzle activities (yellow icons)?
    2. "opened_hexagon_activity": Do you see the Hexagon game interface? It consists of a grid of grey hexagonal cells.
    3. "active_search": Do you see evidence of the game being played? Specifically, do you see hexagons that have turned colors (Red, Yellow, Blue, or Black) after being clicked?
    4. "found_strawberry": Do you see the hidden strawberry revealed on the grid, or a success animation (like a flower or penguin appearing)?
    
    Return JSON:
    {
        "visited_puzzles_category": boolean,
        "opened_hexagon_activity": boolean,
        "active_search": boolean,
        "found_strawberry": boolean,
        "explanation": "brief description of what you saw"
    }
    """

    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_data = {}
    if vlm_result and "parsed" in vlm_result:
        vlm_data = vlm_result["parsed"]
    else:
        feedback.append("VLM analysis failed or returned invalid data.")

    # 4. Scoring Logic
    
    # Criterion A: Agent output file (20 points)
    # Evidence that the agent *thought* it finished and knew how to save a screenshot
    if output_exists and file_created_during and output_size > 10000:
        score += 20
        feedback.append("Agent successfully saved a screenshot file.")
    elif output_exists:
        score += 5
        feedback.append("Agent saved a file, but timestamps or size are suspicious.")

    # Criterion B: Navigation (20 points)
    if vlm_data.get("visited_puzzles_category") or vlm_data.get("opened_hexagon_activity"):
        score += 20
        feedback.append("Navigation verified: Agent found the activity.")

    # Criterion C: Active Gameplay (30 points)
    # This prevents 'do nothing' or just opening the window
    if vlm_data.get("active_search"):
        score += 30
        feedback.append("Interaction verified: Agent actively searched (colored cells visible).")
    
    # Criterion D: Success/Completion (30 points)
    # Did they actually find it?
    if vlm_data.get("found_strawberry"):
        score += 30
        feedback.append("Success verified: Strawberry found.")

    # Stability Bonus (avoiding crashes)
    if not app_running:
        feedback.append("Warning: GCompris was closed or crashed at the end.")
    
    # Pass/Fail determination
    # We require at least 70 points AND the strawberry to be found (or strong evidence of search + file)
    passed = (score >= 70) and vlm_data.get("found_strawberry", False)

    full_feedback = f"Score: {score}/100. " + " ".join(feedback) + f" (VLM Explanation: {vlm_data.get('explanation', 'N/A')})"

    return {
        "passed": passed,
        "score": score,
        "feedback": full_feedback
    }