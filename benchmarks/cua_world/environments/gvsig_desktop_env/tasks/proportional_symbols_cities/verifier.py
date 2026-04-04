#!/usr/bin/env python3
"""
Verifier for gvSIG proportional symbols task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_proportional_symbols(traj, env_info, task_info):
    """
    Verifies:
    1. Project file exists and was created during task.
    2. Project file contains reference to POP_MAX field (XML check).
    3. Exported PNG image exists and is valid size.
    4. VLM confirms the image shows proportional symbols (varying sizes).
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Project File (30 pts)
    if result.get('project_exists') and result.get('project_created_during_task'):
        score += 15
        feedback_parts.append("Project file created.")
        
        # Check content for POP_MAX
        content = result.get('project_content_snippet', '')
        if 'POP_MAX' in content:
            score += 15
            feedback_parts.append("Project correctly references 'POP_MAX' field.")
        else:
            feedback_parts.append("Project does NOT appear to use 'POP_MAX' field.")
    else:
        feedback_parts.append("Project file not saved or not new.")

    # 2. Check Exported Image (30 pts)
    image_exists = result.get('image_exists') and result.get('image_created_during_task')
    image_size = result.get('image_size', 0)
    
    if image_exists:
        if image_size > 10000: # minimal size for a real map
            score += 30
            feedback_parts.append("Map image exported successfully.")
        else:
            score += 10
            feedback_parts.append("Map image exported but seems empty/too small.")
    else:
        feedback_parts.append("Map image not exported.")

    # 3. VLM Verification (40 pts)
    # We check the exported image if available, otherwise the final screenshot
    vlm_score = 0
    
    # Decide which image to use for VLM
    # Ideally use the exported file if we can access it, but we can't easily copy binary image back 
    # and pass to VLM in this flow unless we copy it to a temp path.
    # The 'traj' object has screenshots. We'll use trajectory frames + final screenshot.
    
    frames = sample_trajectory_frames(traj, n=3)
    final_screen = get_final_screenshot(traj)
    images_to_check = frames + [final_screen]
    
    prompt = """
    You are verifying a GIS task. The user was supposed to create a map of world cities where the city points (circles) vary in size based on population (Proportional/Graduated Symbols).
    
    Look at the images, especially the final map or interface.
    1. Do you see a map with points (cities) and background countries?
    2. Are the points DIFFERENT sizes (some large, some small)? Or are they all identical in size?
    3. If you see a legend, does it show graduated symbols (circles of increasing size)?
    
    Answer 'YES' if you clearly see points of VARYING sizes indicating population.
    Answer 'NO' if all points are the same size or if there is no map.
    """
    
    try:
        vlm_resp = query_vlm(images=images_to_check, prompt=prompt).strip().upper()
        if "YES" in vlm_resp:
            vlm_score = 40
            feedback_parts.append("VLM confirmed proportional symbols visible.")
        else:
            feedback_parts.append("VLM did NOT see proportional symbols (points looked uniform or missing).")
    except Exception as e:
        logger.error(f"VLM error: {e}")
        # Fallback partial credit if file checks passed
        if score >= 40:
            vlm_score = 20
            feedback_parts.append("VLM check failed (system error), giving partial credit.")

    score += vlm_score

    # Final tally
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }