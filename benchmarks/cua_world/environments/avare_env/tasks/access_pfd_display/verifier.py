#!/usr/bin/env python3
"""
Verifier for access_pfd_display task.

Verifies that the agent:
1. Started on Map
2. Visited the PFD (Primary Flight Display)
3. Returned to the Map

Uses VLM to classify trajectory frames.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any, List

# Import VLM utilities from framework
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_access_pfd_display(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify Map -> PFD -> Map workflow using VLM trajectory analysis.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve programmatic result (timestamps, app state)
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: In Android envs, copy_from_env usually maps to the device path or a mount
        # We assume the framework handles pulling from /sdcard/task_result.json
        copy_from_env("/sdcard/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution data"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    app_running = result_data.get("app_running", False)
    
    # 2. VLM Trajectory Analysis
    # We need to find at least one frame that looks like the PFD, and the final frame must look like the Map.
    
    frames = sample_trajectory_frames(traj, n=6) # Sample 6 frames from the session
    final_frame = get_final_screenshot(traj)
    
    if not frames:
        return {"passed": False, "score": 0, "feedback": "No trajectory frames available"}
    
    # Prepare VLM prompt
    prompt = """
    You are an aviation app verifier. I will provide a sequence of screenshots from the 'Avare' GPS app.
    
    Please classify each image into one of these categories:
    1. 'PFD': Shows Primary Flight Display with flight instruments (artificial horizon, speed tape, altitude tape, compass rose).
    2. 'MAP': Shows a moving map / aviation chart view.
    3. 'OTHER': Shows menus, dialogs, or other screens.
    
    Goal: The user must start at MAP, go to PFD, and return to MAP.
    
    Analyze the frames and return a JSON object with:
    - "pfd_visited": true if any frame clearly shows the PFD instruments.
    - "final_state": "MAP", "PFD", or "OTHER" (based on the LAST image provided).
    - "workflow_valid": true if you see a sequence like Map -> PFD -> Map (or PFD appears before the final Map).
    - "reasoning": Brief explanation.
    """
    
    # Combine frames + final frame for analysis
    # We send them as a list. The VLM should treat the last one as the final state.
    all_images = frames + [final_frame] if final_frame else frames
    
    vlm_response = query_vlm(
        prompt=prompt,
        images=all_images
    )
    
    if not vlm_response.get("success"):
        return {"passed": False, "score": 0, "feedback": "VLM verification failed"}
        
    analysis = vlm_response.get("parsed", {})
    logger.info(f"VLM Analysis: {analysis}")
    
    pfd_visited = analysis.get("pfd_visited", False)
    final_state = analysis.get("final_state", "OTHER").upper()
    workflow_valid = analysis.get("workflow_valid", False)
    
    # Scoring
    score = 0
    feedback_parts = []
    
    # Criterion 1: App Running (10 pts)
    if app_running:
        score += 10
    else:
        feedback_parts.append("App crashed or closed.")

    # Criterion 2: PFD Visited (40 pts)
    if pfd_visited:
        score += 40
        feedback_parts.append("PFD tab visited successfully.")
    else:
        feedback_parts.append("Did not detect PFD view (Instruments) in trajectory.")
        
    # Criterion 3: Map Restored (40 pts)
    if final_state == "MAP":
        score += 40
        feedback_parts.append("Returned to Map view.")
    elif final_state == "PFD":
        feedback_parts.append("Ended on PFD tab (forgot to return to Map).")
    else:
        feedback_parts.append(f"Ended on unexpected screen: {final_state}")
        
    # Criterion 4: Workflow (10 pts)
    # Bonus for VLM confirming the sequence, but we can infer it if PFD visited + Final is Map
    if pfd_visited and final_state == "MAP":
        score += 10
    elif workflow_valid:
        score += 10

    passed = (score >= 70) and pfd_visited and (final_state == "MAP")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }