#!/usr/bin/env python3
"""
Verifier for the 'find_details_art' task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_find_details_art(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Navigated to the 'Find the details' activity.
    2. Interacted with the painting interface.
    3. Successfully found details (triggering success state).
    4. Saved the evidence screenshot as requested.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # --- Step 1: Check File Evidence (Programmatic) ---
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Criteria A: Evidence file exists and was created during task (30 pts)
    if result.get("output_exists") and result.get("file_created_during_task"):
        score += 30
        feedback_parts.append("Evidence screenshot created.")
    elif result.get("output_exists"):
        score += 15
        feedback_parts.append("Evidence screenshot exists but timestamp unclear.")
    else:
        feedback_parts.append("Evidence screenshot missing.")

    # Criteria B: App is running (10 pts)
    if result.get("app_was_running"):
        score += 10
        feedback_parts.append("GCompris is running.")

    # --- Step 2: VLM Verification (Visual Trajectory) ---
    # We examine the trajectory to ensure they actually played the game.
    
    frames = sample_trajectory_frames(traj, n=6)
    final_screen = get_final_screenshot(traj)
    
    # Prompt checking for workflow: Navigation -> Activity -> Completion
    prompt = """
    You are verifying an agent performing a task in GCompris educational software.
    The task is "Find the details" in famous paintings.
    
    Look at the sequence of images and answer these questions:
    1. NAVIGATION: Did the agent navigate to a menu with a 'Puzzle' or 'Jigsaw' icon category?
    2. ACTIVITY_START: Is the 'Find the details' activity visible? (Look for a famous painting like Seurat's pointillism park or Van Gogh, with a small square detail shown on the side/bottom to find).
    3. INTERACTION: Is there evidence of the agent moving the mouse or clicking on the painting?
    4. COMPLETION: Is there a success indicator? (A smiley face, a flower, a 'Great' message, or the painting changing to a new one).
    
    Return JSON:
    {
      "navigation_observed": boolean,
      "activity_visible": boolean,
      "interaction_observed": boolean,
      "success_indicator_visible": boolean,
      "explanation": "string"
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_screen], prompt=prompt)
    
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        # Scoring VLM findings
        if parsed.get("navigation_observed"):
            score += 10
            feedback_parts.append("Navigation verified.")
            
        if parsed.get("activity_visible"):
            score += 20
            feedback_parts.append("Activity interface verified.")
            
        if parsed.get("interaction_observed"):
            score += 10
            feedback_parts.append("Interaction verified.")
            
        if parsed.get("success_indicator_visible"):
            score += 20
            feedback_parts.append("Level completion verified.")
            
        logger.info(f"VLM Analysis: {parsed.get('explanation')}")
    else:
        feedback_parts.append("VLM verification failed (technical error).")
        # Fallback: if file exists and looks large enough, give partial credit
        if result.get("output_size_bytes", 0) > 50000:
            score += 20
            feedback_parts.append("File size indicates content present.")

    # Pass threshold
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }