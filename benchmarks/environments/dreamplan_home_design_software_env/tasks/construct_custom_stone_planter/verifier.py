#!/usr/bin/env python3
"""
Verifier for Construct Custom Stone Planter task.

Verification Strategy:
1. File Verification (Secondary):
   - Check if stone_planter.dpp exists.
   - Check if it was created/modified during the task.
   - Check if it contains keywords indicative of "Block" and "Plant".
2. VLM Verification (Primary):
   - Use trajectory frames to verify the workflow:
     - Selecting Block tool.
     - Drawing shape.
     - Applying texture.
     - Placing plant.
   - Use final screenshot to verify:
     - Raised block structure in front yard.
     - Stone/Brick texture visible.
     - Plant sitting ON TOP of the block.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_construct_custom_stone_planter(traj, env_info, task_info):
    """
    Verifies that the agent constructed a stone planter with a plant on top.
    """
    # 1. Setup and Copy Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env not available"}

    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        # Continue to VLM if file fails, but penalize
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []

    # 2. File-Based Verification (30 Points)
    output_exists = task_result.get("output_exists", False)
    file_fresh = task_result.get("file_created_during_task", False)
    content_ok = task_result.get("content_keywords_found", False)

    if output_exists:
        score += 10
        feedback.append("Project file saved.")
        if file_fresh:
            score += 10
            feedback.append("File created/modified during task.")
        else:
            feedback.append("Warning: File timestamp indicates it might be old.")
        
        if content_ok:
            score += 10
            feedback.append("Project file contains Block and Plant data.")
        else:
            feedback.append("Could not confirm Block/Plant data in file (might be binary or empty).")
    else:
        feedback.append("Project file 'stone_planter.dpp' not found.")

    # 3. VLM Verification (70 Points)
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    # Prompt for Trajectory (Workflow)
    traj_prompt = """
    Analyze these screenshots of a home design software workflow.
    I am looking for the following actions:
    1. Selecting a "Block" or "Custom Block" tool (usually under Building).
    2. Drawing a shape on the ground.
    3. Changing a material/texture to Stone or Brick.
    4. Selecting a Plant object.
    5. Placing the plant on top of a raised block.

    Does the user perform these actions?
    """
    
    # Prompt for Final State
    final_prompt = """
    Analyze this final screenshot of the 3D home design view.
    I am looking for a specific structure in the Front Yard:
    1. Is there a raised geometric block (like a planter box)?
    2. Does it have a Stone or Brick texture?
    3. Is there a plant (bush/flower) sitting ON TOP of this block?
    4. Is the plant correctly elevated (not hidden inside the block)?

    Respond with JSON:
    {
        "block_visible": true/false,
        "stone_texture": true/false,
        "plant_on_top": true/false,
        "elevation_correct": true/false
    }
    """

    # Query VLM for Workflow
    vlm_traj_res = query_vlm(images=frames, prompt=traj_prompt)
    
    # Query VLM for Final Result
    vlm_final_res = query_vlm(images=[final_img], prompt=final_prompt)

    # Score VLM Results
    if vlm_final_res and vlm_final_res.get("success"):
        parsed = vlm_final_res.get("parsed", {})
        
        if parsed.get("block_visible"):
            score += 20
            feedback.append("Visual: Custom block structure detected.")
        else:
            feedback.append("Visual: No custom block structure found.")
            
        if parsed.get("stone_texture"):
            score += 15
            feedback.append("Visual: Stone/Brick texture detected.")
        else:
            feedback.append("Visual: Texture does not look like stone/brick.")
            
        if parsed.get("plant_on_top"):
            score += 20
            feedback.append("Visual: Plant detected on top of block.")
        else:
            feedback.append("Visual: No plant found on top of the block.")
            
        if parsed.get("elevation_correct"):
            score += 15
            feedback.append("Visual: Plant elevation appears correct.")
    else:
        feedback.append("VLM analysis failed or was inconclusive.")

    # 4. Final Determination
    passed = score >= 70 and output_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }