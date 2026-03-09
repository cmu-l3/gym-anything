#!/usr/bin/env python3
"""
Verifier for configure_scale_dependency task.

Verifies:
1. Project file existence and validity (zip/xml structure).
2. Configuration of scale dependency for specific layer.
3. Correct threshold value (20,000,000).
4. VLM verification of UI interaction.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_scale_dependency(traj, env_info, task_info):
    """
    Verify the scale dependency task.
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
    
    # 1. Project File Checks (40 pts)
    project_exists = result.get('project_exists', False)
    created_during = result.get('project_created_during_task', False)
    
    if project_exists:
        score += 20
        feedback_parts.append("Project file saved.")
        if created_during:
            score += 20
            feedback_parts.append("Project created during task.")
        else:
            feedback_parts.append("Project file timestamp is old.")
    else:
        feedback_parts.append("Project file NOT found.")

    # 2. Configuration Analysis (30 pts)
    xml_valid = result.get('xml_content_valid', False)
    scale_found = result.get('scale_config_found', False)
    target_found = result.get('target_value_found', False)
    
    if xml_valid:
        if target_found:
            score += 30
            feedback_parts.append("Scale threshold 20,000,000 found in configuration.")
        elif scale_found:
            score += 15
            feedback_parts.append("Scale configuration tags found, but specific value 20,000,000 not detected.")
        else:
            feedback_parts.append("Layer found in project, but no scale configuration detected.")
    
    # 3. VLM Verification (30 pts)
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    # Verify interaction with Layer Properties dialog
    prompt = """
    Review the screenshots of the agent using gvSIG Desktop.
    
    Look for:
    1. The "Layer Properties" dialog being open.
    2. Interaction with a "Scale", "General", or "Display" tab within properties.
    3. Inputting the value "20000000" or "1:20000000".
    4. The Populated Places layer (dots) appearing or disappearing when zooming.
    
    Did the agent perform the scale configuration task?
    """
    
    vlm_result = query_vlm(images=frames + [final], prompt=prompt).lower()
    
    if "yes" in vlm_result and ("properties" in vlm_result or "scale" in vlm_result):
        score += 30
        feedback_parts.append("VLM confirms correct UI interaction.")
    else:
        # Fallback partial credit if file is perfect
        if target_found:
            score += 10
            feedback_parts.append("VLM did not clearly see the interaction, but file config is correct.")
        else:
            feedback_parts.append("VLM did not observe the expected workflow.")

    # Final logic
    passed = score >= 60 and project_exists and (target_found or "yes" in vlm_result)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }