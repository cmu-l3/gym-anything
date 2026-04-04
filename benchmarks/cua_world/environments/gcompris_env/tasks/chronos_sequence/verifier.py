#!/usr/bin/env python3
"""
Verifier for Chronos Sequence task in GCompris.
Uses VLM trajectory analysis to verify navigation, sorting interaction, and success state.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chronos_sequence(traj, env_info, task_info):
    """
    Verify the agent completed the Chronos sequencing task.
    """
    # 1. Setup and Basic Checks
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve local result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic criteria
    app_running = result_data.get("app_running", False)
    data_modified = result_data.get("data_modified", False)
    
    score = 0
    feedback_parts = []

    if app_running:
        score += 10
        feedback_parts.append("GCompris was running at end.")
    
    if data_modified:
        score += 10
        feedback_parts.append("GCompris data/config modified (activity recorded).")

    # 2. VLM Trajectory Analysis
    # We need to see: 
    # A) Navigation to Chronos (Timeline/History icon)
    # B) Dragging items (state change)
    # C) Correct order / Success feedback
    
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)

    if not frames:
        return {"passed": False, "score": score, "feedback": "No trajectory frames available for VLM."}

    prompt = """
    You are analyzing a user session in GCompris educational software. 
    The user is supposed to perform the "Chronos" activity, which involves arranging images in chronological order (e.g., history of transportation, plants).

    Review the sequence of images and answer the following:

    1. **Activity Identification**: Do you see the "Chronos" activity? It typically looks like a set of shuffled images (like old planes, cars, or plant stages) labeled with a question mark or timeline.
    2. **Interaction**: Do the images move or change positions across the frames? (Evidence of dragging/sorting).
    3. **Completion**: In the final frames, are the images arranged in a logical order (e.g., Wright flyer -> Propeller -> Jet)? 
    4. **Success Indicator**: Is there a "Great", "Success", star, flower, or Tux (penguin) animation visible indicating the puzzle is solved?

    Return valid JSON:
    {
        "chronos_visible": true/false,
        "sorting_observed": true/false,
        "logical_order_achieved": true/false,
        "success_feedback_visible": true/false,
        "description": "brief description of what is seen"
    }
    """

    vlm_response = query_vlm(images=frames, prompt=prompt)
    
    vlm_data = {}
    if vlm_response and vlm_response.get('success'):
        vlm_data = vlm_response.get('parsed', {})
    else:
        feedback_parts.append("VLM verification failed.")
    
    # Scoring based on VLM
    if vlm_data.get("chronos_visible", False):
        score += 20
        feedback_parts.append("Chronos activity identified.")
    
    if vlm_data.get("sorting_observed", False):
        score += 30
        feedback_parts.append("Sorting interaction observed.")
        
    if vlm_data.get("logical_order_achieved", False):
        score += 10
        feedback_parts.append("Logical order observed.")

    if vlm_data.get("success_feedback_visible", False):
        score += 20
        feedback_parts.append("Success animation verified.")

    # Calculate final result
    # Max score: 10 (app) + 10 (data) + 20 (nav) + 30 (interact) + 10 (order) + 20 (success) = 100
    
    passed = score >= 80  # Requires most steps to be correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts),
        "details": vlm_data
    }