#!/usr/bin/env python3
"""
Verifier for switch_volume_presets_export task.

Scoring (100 points total):
1. Airway rendering exists, is valid PNG, and created during task (25 pts)
2. Soft tissue rendering exists, is valid PNG, and created during task (25 pts)
3. Files are distinct (visual content differs) (15 pts)
4. VLM Verification:
   - Volume rendering (3D) was active (20 pts)
   - Interface shows different presets being selected or visible (15 pts)

Pass Threshold: 60 points (Must have at least one valid file and VLM confirmation)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_switch_volume_presets(traj, env_info, task_info):
    """
    Verify that the agent exported two distinct volume renderings using different presets.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_size = metadata.get('min_file_size_bytes', 30720) # 30KB

    score = 0
    feedback_parts = []
    
    # 1. File-based Verification
    # --------------------------
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check Airway File (25 pts)
    airway_ok = False
    if result.get("airway_exists"):
        if not result.get("airway_valid_png"):
            feedback_parts.append("Airway file exists but is not a valid PNG.")
        elif not result.get("airway_created_during_task"):
            feedback_parts.append("Airway file timestamp indicates it was not created during this task.")
        elif result.get("airway_size") < min_size:
            feedback_parts.append(f"Airway file too small ({result.get('airway_size')} bytes).")
        else:
            score += 25
            airway_ok = True
            feedback_parts.append("Airway rendering exported successfully.")
    else:
        feedback_parts.append("Airway rendering file not found.")

    # Check Soft Tissue File (25 pts)
    softtissue_ok = False
    if result.get("softtissue_exists"):
        if not result.get("softtissue_valid_png"):
            feedback_parts.append("Soft tissue file exists but is not a valid PNG.")
        elif not result.get("softtissue_created_during_task"):
            feedback_parts.append("Soft tissue file timestamp indicates it was not created during this task.")
        elif result.get("softtissue_size") < min_size:
            feedback_parts.append(f"Soft tissue file too small ({result.get('softtissue_size')} bytes).")
        else:
            score += 25
            softtissue_ok = True
            feedback_parts.append("Soft tissue rendering exported successfully.")
    else:
        feedback_parts.append("Soft tissue rendering file not found.")

    # Check Distinctness (15 pts)
    if airway_ok and softtissue_ok:
        if result.get("files_are_distinct"):
            score += 15
            feedback_parts.append("Files are distinct.")
        else:
            feedback_parts.append("WARNING: Exported files are identical (same preset used?).")

    # 2. VLM Verification
    # -------------------
    vlm_score = 0
    
    # Sample frames to catch the workflow
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    if final_screen:
        frames.append(final_screen)

    if not frames:
         feedback_parts.append("No visual evidence available for verification.")
    else:
        prompt = """
        You are verifying a medical software task in InVesalius 3.
        The user was supposed to:
        1. Enable 3D Volume Rendering (raycasting).
        2. Select an 'Airways' preset.
        3. Select a 'Soft Tissue' or 'Brain' preset.
        
        Look at the provided screenshots from the user's session.
        
        Question 1: Is a 3D volume rendering (a colored 3D skull/head model) visible in the large view panel in ANY frame? (Ignore standard black-and-white 2D slices).
        Question 2: Does the visualization style change during the session (e.g., changing from bone color to pink/red soft tissue or transparent airways)?
        Question 3: Is there any evidence of a preset menu being opened or changed?
        
        Reply with JSON:
        {
            "3d_rendering_visible": true/false,
            "style_change_detected": true/false,
            "preset_interaction": true/false
        }
        """
        
        try:
            vlm_resp = query_vlm(images=frames, prompt=prompt)
            parsed = vlm_resp.get("parsed", {})
            
            if parsed.get("3d_rendering_visible"):
                vlm_score += 20
                feedback_parts.append("VLM confirmed 3D volume rendering.")
            else:
                feedback_parts.append("VLM did not see 3D volume rendering.")
                
            if parsed.get("style_change_detected") or parsed.get("preset_interaction"):
                vlm_score += 15
                feedback_parts.append("VLM confirmed preset interaction/change.")
            else:
                feedback_parts.append("VLM did not detect preset change/interaction.")
                
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            # Fallback: if files are valid and distinct, grant partial VLM points
            if airway_ok and softtissue_ok and result.get("files_are_distinct"):
                vlm_score += 20
                feedback_parts.append("VLM check failed, but distinct valid outputs suggest success.")

    total_score = score + vlm_score
    
    # Pass logic: Must have at least one file valid AND some VLM confirmation or distinct files
    passed = (total_score >= 60) and (airway_ok and softtissue_ok)

    return {
        "passed": passed,
        "score": min(100, total_score),
        "feedback": " | ".join(feedback_parts)
    }