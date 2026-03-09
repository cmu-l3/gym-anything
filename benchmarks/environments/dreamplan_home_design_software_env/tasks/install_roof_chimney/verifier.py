#!/usr/bin/env python3
"""
Verifier for install_roof_chimney task.

Verification Strategy:
1. VLM Process (Trajectory): Check if agent navigated to Roof/Chimney tools.
2. VLM Outcome (Final Screenshot): Check if a brick chimney is visible on the roof.
3. File System: Check if the project file was saved/modified (anti-gaming).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_install_roof_chimney(traj, env_info, task_info):
    """
    Verify the installation of a roof chimney in DreamPlan.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Internal Verification Data (File Checks)
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Criterion 1: Project File Modified (20 points)
    if result_data.get("file_modified", False):
        score += 20
        feedback_parts.append("Project file saved/modified successfully.")
    else:
        feedback_parts.append("Project file was NOT saved or modified.")

    # 2. VLM Trajectory & Final State Verification
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if not final_screen:
         return {"passed": False, "score": score, "feedback": "No final screenshot available for VLM."}

    # VLM Query
    # We combine frames and final screen to check process and outcome
    prompt = """
    You are evaluating a user using Home Design software. 
    The goal is to install a Brick Chimney on the Roof of the house.
    
    Analyze the images (chronological trajectory + final state).
    
    Check for:
    1. Did the user access the 'Roof', 'Building', or 'Accessories' menu?
    2. Did the user select a Chimney object?
    3. In the FINAL image, is there a visible vertical chimney structure PROTRUDING from the roof?
    4. Is the chimney texture Brick (red/brown masonry)?
    5. Is the chimney correctly placed on the roof (not floating in sky, not on the grass)?
    
    Respond in JSON:
    {
        "menu_accessed": true/false,
        "chimney_visible": true/false,
        "is_brick": true/false,
        "is_on_roof": true/false,
        "confidence": "low/medium/high"
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_screen], prompt=prompt)
    
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        # Criterion 2: Process (Menu/Object Selection) (20 points)
        if parsed.get("menu_accessed", False):
            score += 20
            feedback_parts.append("Correctly navigated to Roof/Accessories tools.")
        
        # Criterion 3: Chimney Visible (30 points)
        if parsed.get("chimney_visible", False):
            score += 30
            feedback_parts.append("Chimney is visible in the design.")
            
            # Criterion 4: Material Check (15 points)
            if parsed.get("is_brick", False):
                score += 15
                feedback_parts.append("Chimney has correct brick material.")
            else:
                feedback_parts.append("Chimney material does not look like brick.")

            # Criterion 5: Placement Check (15 points)
            if parsed.get("is_on_roof", False):
                score += 15
                feedback_parts.append("Chimney is correctly placed on the roof.")
            else:
                feedback_parts.append("Chimney placement seems incorrect (floating or on ground).")
        else:
            feedback_parts.append("No chimney found in the final design.")
            
    else:
        feedback_parts.append("VLM verification failed to process images.")

    # Final Pass Check
    # Must have file modified AND chimney visible AND placed on roof
    pass_threshold = 70
    passed = (score >= pass_threshold) and result_data.get("file_modified", False) and parsed.get("chimney_visible", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }