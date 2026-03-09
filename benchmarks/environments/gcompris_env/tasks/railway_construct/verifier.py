#!/usr/bin/env python3
"""
Verifier for GCompris Railway Construction Task.

Verification Strategy:
1. File Verification (30 points):
   - Checks if the user saved a screenshot as requested.
   - Checks if the file was created *during* the task (anti-gaming).

2. VLM Trajectory Verification (70 points):
   - Navigation: Did the agent find the Railway activity?
   - Construction: Did the agent place tracks on the grid?
   - Success: Did the train reach the station (success animation)?
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_railway_construct(traj, env_info, task_info):
    """
    Verify the railway construction task using VLM on trajectory frames
    and file-based evidence.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # Load result JSON from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # ------------------------------------------------------------------
    # CRITERION 1: File Evidence (30 Points)
    # ------------------------------------------------------------------
    output_exists = result_data.get("output_exists", False)
    created_during = result_data.get("file_created_during_task", False)
    valid_size = result_data.get("output_size_bytes", 0) > 1000  # Empty images are usually tiny

    if output_exists and created_during and valid_size:
        score += 30
        feedback.append("Success screenshot saved correctly.")
    elif output_exists:
        score += 10
        feedback.append("Screenshot exists but timestamp/size verification failed.")
    else:
        feedback.append("Success screenshot NOT found.")

    # ------------------------------------------------------------------
    # CRITERION 2: VLM Trajectory Verification (70 Points)
    # ------------------------------------------------------------------
    # We sample frames to see the progression: Menu -> Grid -> Tracks -> Success
    frames = sample_trajectory_frames(traj, n=6)
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        frames.append(final_screenshot)

    if not frames:
        return {"passed": False, "score": score, "feedback": "No video evidence available."}

    vlm_prompt = """
    You are analyzing a screen recording of a user playing the 'Railway' educational game in GCompris.
    
    The goal is to:
    1. Open the Railway activity (looks like a train/tracks icon).
    2. Build a track connecting the train engine to the station.
    3. Run the train to complete the level.

    Look at the sequence of images and answer the following in JSON format:
    {
        "activity_opened": boolean, // Did the user navigate to the Railway/Train activity?
        "tracks_placed": boolean,   // Do you see new track pieces appearing on the grid?
        "path_connected": boolean,  // Is there a continuous track from start to end?
        "success_state": boolean,   // Do you see the train at the station OR a 'Great/OK' success message?
        "description": "string"     // Briefly describe what happened.
    }
    """

    vlm_response = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_response.get("success"):
        parsed = vlm_response.get("parsed", {})
        
        # Scoring logic based on VLM analysis
        if parsed.get("activity_opened"):
            score += 15
            feedback.append("VLM confirmed Railway activity was opened.")
        
        if parsed.get("tracks_placed"):
            score += 15
            feedback.append("VLM confirmed tracks were placed on the grid.")
            
        if parsed.get("path_connected"):
            score += 20
            feedback.append("VLM confirmed a connected path was built.")
            
        if parsed.get("success_state"):
            score += 20
            feedback.append("VLM confirmed level completion (success state).")
        
        feedback.append(f"VLM Note: {parsed.get('description', '')}")
    else:
        feedback.append("VLM verification failed to process images.")

    # ------------------------------------------------------------------
    # Final Result Calculation
    # ------------------------------------------------------------------
    # Pass threshold: 60 points.
    # This requires at least: File Evidence (30) + Activity Open (15) + Tracks Placed (15)
    # OR: Full VLM success (70) even if file is missing (partial credit, but fail threshold)
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }