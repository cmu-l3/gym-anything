#!/usr/bin/env python3
"""
Verifier for modify_implant_parameters task in Blue Sky Plan.

Verification Logic:
1. Primary: Check if the project file (.bsp) was modified and its content hash changed.
2. Secondary: VLM verification of the trajectory to confirm:
   - Visual selection of the implant.
   - Visual change in angulation (tilt).
   - Visual change in depth.
   - User interaction with 3D/Cross-section views.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_modify_implant_parameters(traj, env_info, task_info):
    """
    Verifies that the agent modified the implant parameters correctly.
    """
    # 1. Setup and Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths in the Windows VM (using forward slashes works with many copy impls, or raw strings)
    # The Setup script saved result to C:\Users\Docker\AppData\Local\Temp\task_result.json
    # We need to map this to the copy_from_env format. 
    # Usually copy_from_env takes absolute path inside guest.
    guest_result_path = r"C:\Users\Docker\AppData\Local\Temp\task_result.json"
    
    score = 0
    feedback_parts = []
    
    # Retrieve programmatic result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(guest_result_path, temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result JSON from VM"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Programmatic Checks (40 points)
    
    # Criterion 1: File Modified (20 pts)
    if result_data.get('file_modified_during_task', False):
        score += 20
        feedback_parts.append("Project file saved successfully")
    else:
        feedback_parts.append("Project file NOT saved or modified")

    # Criterion 2: Content Changed/Hash (20 pts)
    # This prevents just "Ctrl+S" without doing anything if the app detects no changes,
    # though mostly it verifies the file isn't identical to start.
    if result_data.get('hash_changed', False):
        score += 20
        feedback_parts.append("Project content modified")
    else:
        feedback_parts.append("Project content identical to start (no changes made?)")

    # 3. VLM Verification (60 points)
    # We need to see the visual changes.
    
    frames = sample_trajectory_frames(traj, n=6)
    final_screen = get_final_screenshot(traj)
    
    # Prompt for VLM
    prompt = """
    You are verifying a dental implant planning task in Blue Sky Plan software.
    
    Goal:
    1. Select an existing implant (screw shape).
    2. Tilt it ~10 degrees lingually (towards the tongue side).
    3. Make it deeper (move it down into the bone).
    
    Review the image sequence. 
    1. Do you see the user selecting the implant or opening a properties/parameters panel?
    2. Compare the start and end states (or intermediate steps). Does the implant's angle change? (It should look more tilted).
    3. Does the implant's depth change? (It should sit lower in the bone).
    4. Did the user view the Cross-Section (slice) view?
    
    Output JSON:
    {
      "implant_selected_or_edited": true/false,
      "angulation_changed_visually": true/false,
      "depth_changed_visually": true/false,
      "cross_section_view_used": true/false,
      "confidence": "high/medium/low"
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_screen], prompt=prompt)
    
    if vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        
        if parsed.get('implant_selected_or_edited'):
            score += 10
            feedback_parts.append("VLM: Implant interaction detected")
            
        if parsed.get('angulation_changed_visually'):
            score += 20
            feedback_parts.append("VLM: Angulation change confirmed")
        
        if parsed.get('depth_changed_visually'):
            score += 20
            feedback_parts.append("VLM: Depth change confirmed")
            
        if parsed.get('cross_section_view_used'):
            score += 10
            feedback_parts.append("VLM: Cross-section verified")
    else:
        feedback_parts.append("VLM verification failed")

    # 4. Final Assessment
    # Pass if file modified AND at least one visual change confirmed
    visual_confirmation = (score >= 60) # Implies at least some VLM points + file points
    file_confirmation = result_data.get('file_modified_during_task', False)
    
    passed = file_confirmation and (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }