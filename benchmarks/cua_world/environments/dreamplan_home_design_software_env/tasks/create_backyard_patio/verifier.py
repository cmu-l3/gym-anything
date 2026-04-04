#!/usr/bin/env python3
"""
Verifier for Create Backyard Patio task.

Verification Strategy:
1. File Verification (Secondary):
   - Check if a DreamPlan project file was modified or created during the task.
   - This prevents "do nothing" but doesn't verify content (proprietary binary format).

2. VLM Verification (Primary):
   - Use trajectory frames to verify the workflow (selecting tools, drawing).
   - Use the final screenshot to verify the specific visual requirements:
     a) Patio exists in backyard (location check).
     b) Texture is stone/paved (material check).
     c) Shape is roughly rectangular.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_backyard_patio(traj, env_info, task_info):
    """
    Verify the backyard patio creation task using VLM and file timestamps.
    """
    # 1. Setup and File Check
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Retrieve file metrics from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Windows path in container maps to C:\tmp\task_result.json
        # The copy_from_env usually handles the mapping from the guest OS path
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            file_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy/read result: {e}")
        file_result = {}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Score File Evidence (20 points)
    if file_result.get("file_modified_during_task", False):
        score += 20
        feedback_parts.append("Project file saved/modified.")
    elif file_result.get("file_found", False):
        score += 5
        feedback_parts.append("Project file found but NOT modified (did you save?).")
    else:
        feedback_parts.append("No project file found.")

    # 2. VLM Verification (80 points)
    # We use the final screenshot for the end result and trajectory for process
    
    final_img = get_final_screenshot(traj)
    traj_frames = sample_trajectory_frames(traj, n=4)
    
    if not final_img:
        return {"passed": False, "score": score, "feedback": "No screenshots available for verification."}

    # Prompt for VLM
    prompt = """
    You are verifying a home design task. The goal was to create a STONE PATIO in the BACKYARD.
    
    Please analyze the images. The last image is the final result. The previous images show the process.
    
    Check for the following:
    1. **Patio Existence**: Is there a visible paved area added to the ground?
    2. **Location**: Is it in the BACKYARD (behind the house)?
       - Front yard usually has a driveway or path to front door.
       - Backyard is usually open grass or has a deck.
    3. **Material**: Does the surface look like STONE, FLAGSTONE, or PAVERS? (Not just green grass or plain grey concrete).
    4. **Shape**: Is it roughly rectangular?
    
    Respond in JSON:
    {
        "patio_visible": true/false,
        "location_is_backyard": true/false,
        "material_looks_like_stone": true/false,
        "workflow_showing_creation": true/false,
        "explanation": "Brief description of what you see"
    }
    """
    
    vlm_response = query_vlm(images=traj_frames + [final_img], prompt=prompt)
    
    if vlm_response.get("success"):
        parsed = vlm_response.get("parsed", {})
        
        # Scoring Criteria
        if parsed.get("patio_visible", False):
            score += 25
            feedback_parts.append("Patio visible.")
        else:
            feedback_parts.append("No patio visible in final view.")
            
        if parsed.get("location_is_backyard", False):
            score += 20
            feedback_parts.append("Located in backyard.")
        else:
            feedback_parts.append("Location incorrect (not clearly backyard).")
            
        if parsed.get("material_looks_like_stone", False):
            score += 15
            feedback_parts.append("Stone material applied.")
        else:
            feedback_parts.append("Material does not look like stone/pavers.")

        if parsed.get("workflow_showing_creation", False):
            score += 20
            feedback_parts.append("Workflow confirmed.")
    else:
        feedback_parts.append("Visual verification failed to run.")

    # Final tally
    passed = score >= 60 and parsed.get("patio_visible", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }