#!/usr/bin/env python3
"""
Verifier for install_interior_archway task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_install_interior_archway(traj, env_info, task_info):
    """
    Verifies that the agent installed an interior archway.
    
    Strategy:
    1. VLM (Primary): Check trajectory for "Arches" category selection and final 3D view of an open arch.
    2. System (Secondary): Check if project file was saved/modified.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Fetch System Results
    system_result = {}
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            system_result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        logger.warning(f"Failed to read task_result.json: {e}")

    # 2. VLM Verification
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    # Prompt for Process Verification (Category Selection)
    process_prompt = """
    You are verifying a user interacting with home design software.
    Look at these screenshots of the workflow.
    
    Did the user navigate to a "Doors" or "Openings" library?
    Did they specifically select an "Arch", "Archway", or "Cased Opening" category?
    (They should NOT have selected a standard hinged/solid door).
    
    Return JSON:
    {
        "doors_library_opened": true/false,
        "arches_category_selected": true/false,
        "wrong_item_selected": true/false
    }
    """
    
    # Prompt for Final Result (Visual Check)
    result_prompt = """
    Look at the final screenshot of the home design 3D view.
    
    Is there a new opening in an interior wall?
    Is this opening an ARCHWAY or CASED OPENING (meaning you can see clearly through it, no door panel)?
    Or is it a solid door (blocking the view)?
    
    Return JSON:
    {
        "wall_opening_visible": true/false,
        "is_open_archway": true/false,
        "is_solid_door": true/false
    }
    """
    
    vlm_process = query_vlm(images=frames, prompt=process_prompt).get('parsed', {})
    vlm_result = query_vlm(image=final_frame, prompt=result_prompt).get('parsed', {})
    
    # 3. Scoring
    score = 0
    feedback = []
    
    # Criterion 1: Project Modified (15 pts)
    if system_result.get('project_modified', False):
        score += 15
        feedback.append("Project file saved.")
    else:
        feedback.append("Project file NOT saved.")
        
    # Criterion 2: Process - Library Navigation (25 pts)
    if vlm_process.get('doors_library_opened', False):
        score += 10
        feedback.append("Opened Doors library.")
    if vlm_process.get('arches_category_selected', False):
        score += 15
        feedback.append("Selected Arches/Openings category.")
    elif vlm_process.get('wrong_item_selected', False):
        feedback.append("Selected wrong item type (e.g. solid door).")

    # Criterion 3: Final Visual Result (60 pts)
    if vlm_result.get('wall_opening_visible', False):
        score += 20
        feedback.append("Opening visible in wall.")
        
        if vlm_result.get('is_open_archway', False):
            score += 40
            feedback.append("Correctly installed an open archway.")
        elif vlm_result.get('is_solid_door', False):
            feedback.append("Incorrect: Installed a solid door instead of an archway.")
    else:
        feedback.append("No new wall opening detected in final view.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }