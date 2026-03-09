#!/usr/bin/env python3
"""
Verifier for GCompris Cartesian Coordinates task.
Uses VLM trajectory analysis to verify navigation and gameplay interaction.
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cartesian_coordinates(traj, env_info, task_info):
    """
    Verify the agent navigated to and completed the Cartesian Coordinates level.
    """
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Retrieve result JSON from container
    task_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result data"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Basic Signals
    app_running = task_result.get("app_running", False)
    data_modified = task_result.get("data_modified", False)
    
    # 3. VLM Verification Strategy
    # We use a trajectory of frames to see navigation AND final state
    frames = sample_trajectory_frames(traj, n=5)
    final_frame = get_final_screenshot(traj)
    
    if not frames and not final_frame:
        return {"passed": False, "score": 0, "feedback": "No screenshots available for verification"}
    
    all_images = frames + ([final_frame] if final_frame else [])
    
    # Prompt for the VLM
    prompt = """
    You are evaluating an agent using GCompris educational software.
    The goal is to:
    1. Navigate to the Mathematics category (Sheep/123 icon).
    2. Navigate to the Geometry sub-category.
    3. Open the "Cartesian Coordinates" activity (shows a grid with X/Y axes).
    4. Play the game (click points on grid) and complete Level 1.
    
    Review the sequence of screenshots.
    
    Determine:
    A. Did the agent navigate through the menus? (Are menu icons visible in early frames?)
    B. Is the "Cartesian Coordinates" activity visible in any frame? (Look for a blue/white grid with axes).
    C. Is there evidence of interaction? (Cursor moving, points appearing on grid, inputting numbers).
    D. Is the level COMPLETED? (Look for a "flower" animation, "Tux" saying good job, "Level 2" text, or a checkmark).
    
    Respond in JSON:
    {
        "navigated_menus": true/false,
        "activity_reached": true/false,
        "interaction_observed": true/false,
        "level_completed": true/false,
        "reasoning": "brief explanation"
    }
    """
    
    vlm_response = query_vlm(
        images=all_images,
        prompt=prompt
    )
    
    if not vlm_response.get("success"):
        return {"passed": False, "score": 0, "feedback": "VLM verification failed"}
        
    analysis = vlm_response.get("parsed", {})
    
    # 4. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion 1: App Health (10 pts)
    if app_running:
        score += 10
    else:
        feedback_parts.append("GCompris was closed prematurely.")
        
    # Criterion 2: Navigation (20 pts)
    if analysis.get("navigated_menus"):
        score += 20
        feedback_parts.append("Navigation verified.")
    else:
        feedback_parts.append("Did not demonstrate correct menu navigation.")
        
    # Criterion 3: Activity Reached (20 pts)
    if analysis.get("activity_reached"):
        score += 20
        feedback_parts.append("Cartesian Coordinates activity reached.")
    else:
        feedback_parts.append("Failed to find/open the specific Cartesian activity.")
        
    # Criterion 4: Interaction/Gameplay (20 pts)
    # We combine VLM observation OR file modification as evidence of active play
    if analysis.get("interaction_observed") or data_modified:
        score += 20
        feedback_parts.append("Interaction with activity detected.")
    else:
        feedback_parts.append("No interaction or data progress detected.")
        
    # Criterion 5: Completion (30 pts)
    if analysis.get("level_completed"):
        score += 30
        feedback_parts.append("Level completion verified.")
    else:
        feedback_parts.append("Level completion not observed.")

    # Pass Threshold
    # Must reach activity (20) + Interact (20) + Completion (30) + Navigation/App (10) = ~80
    # Set threshold at 70 to allow for minor misses if core task is done
    passed = (score >= 70) and analysis.get("activity_reached")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts),
        "details": analysis
    }