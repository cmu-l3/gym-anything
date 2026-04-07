#!/usr/bin/env python3
"""
Verifier for courtyard_building_solar task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. File Verification (10 points): Checks if the `.skp` file exists, was created during the task, and >50KB.
2. Geometry Verification (VLM) (25 points): Checks for a U-shaped building.
3. Multi-Zone Solar Verification (VLM) (45 points, 15 per wing): Checks for panels on back, left, and right wings.
4. Setup Configurations (VLM) (10 points): Checks if panels are tilted (not flush).
5. Workflow Trajectory (VLM) (10 points): Ensures progression from drawing geometry to applying Skelion.
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating a SketchUp model to verify a task involving the Skelion solar plugin.
The goal was to create a U-shaped courtyard building (3 wings) and add solar panels to all 3 roofs.

Look at the provided trajectory frames (showing the workflow) and the final screenshot.
Please determine the following criteria:
1. `u_shaped_building_visible`: Is there a clear U-shaped building visible (consisting of 3 rectangular wings forming a U or C shape with an open courtyard)?
2. `panels_on_back_wing`: Are there solar panels placed on the roof of the main/back connecting wing?
3. `panels_on_left_wing`: Are there solar panels placed on the roof of the left wing?
4. `panels_on_right_wing`: Are there solar panels placed on the roof of the right wing?
5. `panels_are_tilted`: Do the solar panels appear to be tilted (e.g., at 10 degrees) rather than lying completely flat/flush on the roof surface?
6. `workflow_progression`: Do the sequence of trajectory frames show a progression from creating the building geometry to using Skelion to place panels on multiple distinct faces?

Respond ONLY in valid JSON format matching this schema:
{
    "u_shaped_building_visible": true/false,
    "panels_on_back_wing": true/false,
    "panels_on_left_wing": true/false,
    "panels_on_right_wing": true/false,
    "panels_are_tilted": true/false,
    "workflow_progression": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_courtyard_building_solar(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env or not query_vlm:
        return {"passed": False, "score": 0, "feedback": "Required evaluation functions (copy_from_env, query_vlm) not available."}

    metadata = task_info.get('metadata', {})
    min_size = metadata.get('min_file_size_bytes', 50000)
    
    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. FILE VERIFICATION
    # ---------------------------------------------------------
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Use Windows-style path that maps to C: in Docker
        copy_from_env("C:/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read file from container: {e}")
        result = {}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    file_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    file_size = result.get('file_size_bytes', 0)
    
    file_valid = False
    if file_exists and file_created and file_size >= min_size:
        score += 10
        file_valid = True
        feedback_parts.append(f"✅ Output file valid ({file_size//1024} KB)")
    elif file_exists:
        feedback_parts.append(f"❌ File exists but invalid (size: {file_size}b, new: {file_created})")
    else:
        feedback_parts.append("❌ Output file not found")

    # ---------------------------------------------------------
    # 2. VLM VERIFICATION (Trajectory + Final State)
    # ---------------------------------------------------------
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    if final_img:
        images_to_evaluate = frames + [final_img]
        vlm_resp = query_vlm(prompt=VLM_PROMPT, images=images_to_evaluate)
        
        if vlm_resp and vlm_resp.get("success"):
            parsed = vlm_resp.get("parsed", {})
            
            # Geometry (25 pts)
            u_shape = parsed.get("u_shaped_building_visible", False)
            if u_shape:
                score += 25
                feedback_parts.append("✅ U-shaped building geometry found")
            else:
                feedback_parts.append("❌ Missing correct U-shaped geometry")
                
            # Solar panels on back wing (15 pts)
            if parsed.get("panels_on_back_wing", False):
                score += 15
                feedback_parts.append("✅ Panels on back wing")
                
            # Solar panels on left wing (15 pts)
            if parsed.get("panels_on_left_wing", False):
                score += 15
                feedback_parts.append("✅ Panels on left wing")
                
            # Solar panels on right wing (15 pts)
            if parsed.get("panels_on_right_wing", False):
                score += 15
                feedback_parts.append("✅ Panels on right wing")
                
            # Panel tilt (10 pts)
            if parsed.get("panels_are_tilted", False):
                score += 10
                feedback_parts.append("✅ Panels are tilted correctly")
                
            # Workflow (10 pts)
            if parsed.get("workflow_progression", False):
                score += 10
                feedback_parts.append("✅ Workflow progression observed")
        else:
            feedback_parts.append("❌ VLM verification failed to process")
    else:
        feedback_parts.append("❌ No screenshots available for VLM verification")
        
    # Minimum required to "Pass": Must have saved the file, built the u-shape, and placed panels on at least 1 wing
    key_criteria_met = file_valid and u_shape and (score >= 60)
    
    return {
        "passed": key_criteria_met,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }