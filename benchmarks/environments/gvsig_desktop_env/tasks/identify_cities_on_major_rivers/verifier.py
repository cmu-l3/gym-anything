#!/usr/bin/env python3
"""
Verifier for identify_cities_on_major_rivers task.

Checks:
1. Output shapefile existence and timestamp.
2. Feature count analysis (must be a subset of original cities).
3. VLM verification of the workflow (filtering, buffering, selection).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_identify_cities_on_major_rivers(traj, env_info, task_info):
    """
    Verify that the agent identified cities near major rivers.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    score = 0
    feedback_parts = []
    
    # 1. File Existence & Validity (30 pts)
    output_exists = result.get('output_exists', False)
    valid_shapefile = result.get('valid_shapefile', False)
    
    if output_exists and valid_shapefile:
        score += 30
        feedback_parts.append("Output shapefile exists and is valid.")
    elif output_exists:
        score += 10
        feedback_parts.append("Output file exists but seems invalid.")
    else:
        feedback_parts.append("Output shapefile not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}

    # 2. Anti-Gaming Timestamp (10 pts)
    if result.get('created_during_task', False):
        score += 10
        feedback_parts.append("File created during task.")
    else:
        feedback_parts.append("File timestamp indicates it was not created during this session.")

    # 3. Content Analysis (30 pts)
    # We expect a subset of cities (not 0, not all)
    output_count = result.get('output_count', 0)
    input_count = result.get('input_count', 243) # approx 243 in NE 110m
    is_subset = result.get('is_subset', False)
    
    if is_subset:
        score += 30
        feedback_parts.append(f"Feature count ({output_count}) is a valid subset of total cities ({input_count}).")
    else:
        if output_count == 0:
            feedback_parts.append("Output shapefile is empty.")
        elif output_count >= input_count:
            feedback_parts.append(f"Output contains all {output_count} cities (filtering failed).")
        else:
            feedback_parts.append(f"Unexpected feature count: {output_count}.")

    # 4. VLM Verification (30 pts)
    # Check if the agent actually performed the steps (Buffer, Select)
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review the screenshots of a GIS workflow in gvSIG Desktop.
    The goal was to:
    1. Filter rivers (scalerank < 4)
    2. Buffer the rivers (0.2 degrees)
    3. Select cities intersecting the buffer
    
    Look for evidence of:
    - A buffer geoprocessing dialog or result (thick lines/polygons around rivers)
    - A selection dialog (Select by Layer / Select by Location)
    - Yellow highlighted features (indicating selection)
    
    Did the agent perform a buffer and spatial selection operation?
    """
    
    vlm_result = query_vlm(images=frames + [final], prompt=vlm_prompt)
    
    if vlm_result.get('answer_bool', False):
        score += 30
        feedback_parts.append("VLM verified workflow steps (Buffering/Selection).")
    else:
        # Partial credit if file analysis was perfect, assuming VLM missed it
        if score >= 70:
            score += 10 
            feedback_parts.append("VLM did not clearly see the workflow, but output is correct.")
        else:
            feedback_parts.append("VLM did not observe the required geoprocessing steps.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }