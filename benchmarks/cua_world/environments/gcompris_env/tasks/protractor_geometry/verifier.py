#!/usr/bin/env python3
"""
Verifier for GCompris Protractor Geometry task.

Verification Strategy:
1. Primary: VLM Trajectory Analysis
   - Verify navigation to Math > Geometry > Protractor activity.
   - Verify interaction with the protractor tool (dragging/rotating).
   - Verify visual feedback of success (flower/animation/checkmark) for at least one problem.
2. Secondary: Evidence File Check
   - Check if agent saved the screenshot as requested.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_protractor_geometry(traj, env_info, task_info):
    """
    Verify the agent correctly used the protractor to measure angles.
    """
    # 1. Setup and load result data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy function not available"}

    # Load the JSON result exported from the container
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
    feedback_parts = []
    
    # 2. File Verification (Evidence Screenshot) - 10 points
    evidence_exists = result_data.get("evidence_exists", False)
    evidence_fresh = result_data.get("evidence_created_during_task", False)
    
    if evidence_exists and evidence_fresh:
        score += 10
        feedback_parts.append("Success screenshot saved correctly.")
    elif evidence_exists:
        score += 5
        feedback_parts.append("Screenshot exists but timestamp is suspicious.")
    else:
        feedback_parts.append("Success screenshot was not saved.")

    # 3. App State Verification - 5 points
    if result_data.get("app_was_running", False):
        score += 5
    else:
        feedback_parts.append("GCompris was closed before verification.")

    # 4. VLM Trajectory Verification - 85 points total
    # We sample frames to see the workflow
    frames = sample_trajectory_frames(traj, n=6)
    final_frame = get_final_screenshot(traj)
    
    if not frames:
        return {"passed": False, "score": score, "feedback": "No trajectory frames available for verification."}

    # Prompt for VLM Analysis
    prompt = """
    You are verifying a user performing a geometry task in GCompris Educational Software.
    The task is to use a virtual protractor to measure angles.
    
    Please analyze the provided sequence of screenshots and answer the following questions in JSON format:
    
    1. "activity_found": (boolean) Do you see the "Measure Angle" or "Protractor" activity? Look for a green angle and a semi-circular protractor tool on screen.
    2. "tool_interaction": (boolean) Does the protractor move or rotate across the frames? (Compare positions of the protractor).
    3. "success_feedback": (boolean) Do you see any visual indication of a correct answer? In GCompris, this is typically a flower icon appearing, a smiley face, a 'Great' message, or the angle changing to a new problem immediately after input.
    4. "multiple_problems": (boolean) Does the angle shape/color or value change, indicating the user moved to a second problem?
    
    JSON Output:
    {
        "activity_found": true/false,
        "tool_interaction": true/false,
        "success_feedback": true/false,
        "multiple_problems": true/false
    }
    """
    
    # Include final frame in analysis
    analysis_frames = frames + [final_frame] if final_frame else frames
    
    vlm_response = query_vlm(
        images=analysis_frames,
        prompt=prompt
    )
    
    vlm_result = {}
    if vlm_response and "result" in vlm_response:
        # Parse the string result from the VLM tool if needed, 
        # but the tool signature suggests it returns a dict with 'result' containing text.
        # We'll assume the helper handles parsing or we try to parse the JSON string.
        try:
            # Clean up potential markdown code blocks
            json_str = vlm_response["result"].replace("