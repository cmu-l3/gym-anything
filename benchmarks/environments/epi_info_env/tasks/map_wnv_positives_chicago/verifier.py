#!/usr/bin/env python3
"""
Verifier for map_wnv_positives_chicago task.

Criteria:
1. Output file (wnv_positive_map.png) exists and is a valid image. (40 pts)
2. Output file was created during the task window. (10 pts)
3. VLM: Trajectory shows filtering action (user interaction with Filter dialog). (20 pts)
4. VLM: Final map content shows points (dots) and map background. (30 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_map_wnv_positives(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # 1. Check File Existence and Timing (from export_result.sh)
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if result_data.get("output_exists"):
        score += 40
        feedback.append("Map image file created.")
        
        if result_data.get("file_created_during_task"):
            score += 10
            feedback.append("File created during task window.")
        else:
            feedback.append("WARNING: File timestamp predates task.")
            
        if result_data.get("output_size_bytes", 0) > 1000:
            feedback.append("File size seems valid.")
        else:
            feedback.append("WARNING: File size suspiciously small.")
    else:
        feedback.append("Map image file NOT found.")

    # 2. VLM Verification
    frames = sample_trajectory_frames(traj, n=5)
    final_screen = get_final_screenshot(traj)
    
    # A. Verify Filter Action (Trajectory)
    filter_prompt = """
    Review these screenshots of a user using Epi Info 7 (Epi Map).
    Look for evidence of DATA FILTERING.
    
    Do you see:
    1. A 'Filter' dialog or panel?
    2. The user typing 'positive' or selecting 'RESULT' field?
    3. Any interaction that suggests restricting the data view?
    
    Return JSON: {"filtering_observed": boolean, "confidence": "low/medium/high", "details": "string"}
    """
    
    try:
        filter_res = query_vlm(images=frames, prompt=filter_prompt)
        filter_parsed = filter_res.get('parsed', {})
        if filter_parsed.get('filtering_observed'):
            score += 20
            feedback.append("VLM confirmed filtering action.")
        else:
            feedback.append("VLM did not detect explicit filtering steps.")
    except Exception as e:
        logger.error(f"VLM Trajectory check failed: {e}")

    # B. Verify Map Content (Final Output or Screen)
    # We verify the screenshot because we can't easily read the PNG content from inside container directly via VLM helper 
    # (unless we download it, but verifying the screen state is usually sufficient proxy for the task goal)
    map_prompt = """
    Analyze this screenshot of the Epi Map application.
    
    Does the main view show a GEOGRAPHIC MAP with DATA POINTS (dots)?
    Are there specific points plotted on the map (not just a blank map)?
    Does it look like a valid Epi Map visualization?
    
    Return JSON: {"map_points_visible": boolean, "valid_map": boolean, "details": "string"}
    """
    
    try:
        map_res = query_vlm(image=final_screen, prompt=map_prompt)
        map_parsed = map_res.get('parsed', {})
        if map_parsed.get('map_points_visible') and map_parsed.get('valid_map'):
            score += 30
            feedback.append("VLM confirmed map visualization with data points.")
        else:
            feedback.append("VLM could not confirm valid map points in final view.")
    except Exception as e:
        logger.error(f"VLM Content check failed: {e}")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }