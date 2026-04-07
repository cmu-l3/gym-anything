#!/usr/bin/env python3
"""
Verifier for scale_model_from_plan task.

VERIFICATION MULTI-SIGNAL STRATEGY:
1. Programmatic: Check if the SketchUp `.skp` file was successfully saved and is a reasonable size (>20KB).
2. Anti-Gaming: Verify the file's modification timestamp to ensure it was created during the task run.
3. VLM Analysis (Trajectory + Final): Validate spatial progression (Image imported -> Tape measure scaling -> 3D Extrusion -> Skelion Panels placed).
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_scale_model_from_plan(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        return {"passed": False, "score": 0, "feedback": "VLM query function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Read exported result JSON from container via copy_from_env
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback_parts.append(f"Failed to read exported result: {e}")
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    file_size = result.get('output_size_bytes', 0)
    
    # Score programmatic file creation (30 points total)
    if output_exists:
        score += 10
        feedback_parts.append("Model file saved")
        if file_created:
            score += 10
            feedback_parts.append("File verified created during session")
        else:
            feedback_parts.append("Warning: File timestamp indicates it was not modified during task")
            
        if file_size > 20000:
            score += 10
            feedback_parts.append("File size is valid (>20KB)")
        else:
            feedback_parts.append(f"File size unusually small ({file_size} bytes)")
    else:
        feedback_parts.append("Model file not found")
        
    # 2. VLM Verification across trajectory
    frames = sample_trajectory_frames(traj, n=5)
    final = get_final_screenshot(traj)
    images = frames + [final] if final else frames
    
    if not images:
        return {"passed": False, "score": score, "feedback": "No images available for VLM verification"}
        
    prompt = """You are verifying an agent's visual performance on a 3D CAD layout task in SketchUp.
    
    TASK GOAL: Import a 2D site plan image, scale the model to match the 25m reference line, trace and extrude a 3D building, and layout solar panels.
    
    Analyze the trajectory and final screenshots and determine:
    1. IMAGE IMPORTED: Is the white/gray site plan image (labeled 'WAREHOUSE') visible on the SketchUp ground plane in any frame?
    2. MODEL SCALED: Is there evidence of the agent scaling the image? Look for the 'Tape Measure' tool interacting with the black scale line, a 'Do you want to resize the model?' dialog, OR a Dimension Line showing approximately '25.00m'.
    3. BUILDING TRACED: Is there a 3D building extruded from the ground that aligns with the gray box footprint from the image?
    4. PANELS INSTALLED: Are there blue/black rectangular Skelion solar panels placed on top of the 3D building?
    
    Return your analysis strictly in valid JSON format:
    {
        "image_imported": true/false,
        "model_scaled": true/false,
        "building_traced": true/false,
        "panels_installed": true/false,
        "reasoning": "Brief justification describing what visual evidence exists for each."
    }
    """
    
    vlm_result = query_vlm(prompt=prompt, images=images)
    
    vlm_parsed = {}
    if vlm_result and vlm_result.get('success'):
        vlm_parsed = vlm_result.get('parsed', {})
    else:
        feedback_parts.append(f"VLM error: {vlm_result.get('error', 'Unknown')}")
        
    # Score VLM progression (70 points total)
    image_imported = vlm_parsed.get('image_imported', False)
    model_scaled = vlm_parsed.get('model_scaled', False)
    building_traced = vlm_parsed.get('building_traced', False)
    panels_installed = vlm_parsed.get('panels_installed', False)
    
    if image_imported:
        score += 10
        feedback_parts.append("VLM: Site plan imported")
    else:
        feedback_parts.append("VLM: Site plan not imported")
        
    if model_scaled:
        score += 25
        feedback_parts.append("VLM: Scaling operation verified")
    else:
        feedback_parts.append("VLM: Model scaling not confirmed")
        
    if building_traced:
        score += 15
        feedback_parts.append("VLM: Extruded 3D building verified")
    else:
        feedback_parts.append("VLM: 3D building missing")
        
    if panels_installed:
        score += 20
        feedback_parts.append("VLM: Solar panels populated")
    else:
        feedback_parts.append("VLM: Solar panels missing")
        
    # Require core workflow and file output for a true pass
    passed = (score >= 80) and output_exists and model_scaled and building_traced and panels_installed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }