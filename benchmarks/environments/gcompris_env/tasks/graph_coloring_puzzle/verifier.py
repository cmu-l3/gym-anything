#!/usr/bin/env python3
"""
Verifier for Graph Coloring Puzzle task.

Verification Strategy:
1. File Check: Did the agent save a screenshot as requested? (Anti-gaming check)
2. VLM Trajectory Check:
   - Did the agent navigate to the correct activity?
   - Did the agent interact with the graph (coloring nodes)?
   - Did the success/congratulations animation appear?
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_graph_coloring_puzzle(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve JSON result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Basic File & State Checks (Max 30 points)
    score = 0
    feedback_parts = []
    
    file_created = result.get('file_created_during_task', False)
    app_running = result.get('app_running', False)
    
    if app_running:
        score += 10
        feedback_parts.append("GCompris was running.")
    
    if file_created:
        score += 20
        feedback_parts.append("Screenshot saved correctly.")
    else:
        feedback_parts.append("Screenshot NOT saved.")

    # 3. VLM Trajectory Verification (Max 70 points)
    # We sample frames to see the progression: Menu -> Activity -> Coloring -> Success
    frames = sample_trajectory_frames(traj, n=5)
    final_screenshot = get_final_screenshot(traj)
    
    if not frames:
        return {"passed": False, "score": score, "feedback": "No trajectory frames available."}

    # Prompt designed to verify specific steps
    prompt = """
    You are analyzing a screen recording of a user playing the 'Graph Coloring' logic game in GCompris.
    
    The game involves:
    1. A graph with nodes (circles) connected by lines.
    2. A palette of colors.
    3. The goal is to color nodes so no two connected nodes have the same color.
    4. A success animation (often a flower, smiley, or 'OK' sign) appears when solved.

    Look at the sequence of images and answer:
    1. Did the user navigate to the Graph Coloring activity? (Do you see nodes/circles connected by lines?)
    2. Did the user interact with the game? (Do the colors of the nodes change across frames?)
    3. Is the puzzle solved? (Do you see a 'Great', 'OK', flower, or victory animation?)
    4. Are there any visible errors (like connected nodes having the same color)?

    Return JSON:
    {
        "activity_found": boolean,
        "interaction_observed": boolean,
        "success_state_reached": boolean,
        "errors_visible": boolean,
        "reasoning": "string"
    }
    """
    
    # Include final screenshot in the analysis
    analysis_images = frames + [final_screenshot] if final_screenshot else frames
    
    vlm_response = query_vlm(images=analysis_images, prompt=prompt)
    
    vlm_score = 0
    if vlm_response and vlm_response.get('success'):
        parsed = vlm_response.get('parsed', {})
        logger.info(f"VLM Analysis: {parsed}")
        
        if parsed.get('activity_found'):
            vlm_score += 20
            feedback_parts.append("Found Graph Coloring activity.")
        
        if parsed.get('interaction_observed'):
            vlm_score += 20
            feedback_parts.append("Interacted with the puzzle.")
            
        if parsed.get('success_state_reached'):
            vlm_score += 30
            feedback_parts.append("Puzzle solved successfully.")
        elif parsed.get('errors_visible'):
            feedback_parts.append("Visible coloring errors detected.")
            
    else:
        feedback_parts.append("VLM verification failed to run.")

    score += vlm_score

    # Passing logic
    # Must have found activity, interacted, and either reached success OR saved the file (partial credit fallback)
    # But for a PASS, we really want the puzzle solved.
    # Threshold: 60 points.
    # Case A: App running (10) + File saved (20) + Activity found (20) + Interaction (20) = 70 (PASS)
    # Case B: App running (10) + Activity found (20) + Interaction (20) + Success (30) = 80 (PASS - even if file missed)
    # Case C: App running (10) + File saved (20) = 30 (FAIL - didn't do the task)
    
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }