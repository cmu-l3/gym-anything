#!/usr/bin/env python3
"""
Verifier for circular_infrastructure_solar task.
Combines programmatic metadata checks with trajectory-based VLM verification.
"""
import json
import os
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_circular_infrastructure(traj, env_info, task_info):
    """
    Verify that the circular array was created and overhanging panels were removed.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Copy and parse result metadata from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Use Windows-style path as configured in the setup/export hooks
        copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # Check File Presence and Integrity (Anti-Gaming)
    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    file_size = result.get('output_size_bytes', 0)
    
    if output_exists:
        score += 10
        feedback_parts.append("File exists")
        
        if file_created:
            score += 15
            feedback_parts.append("File created during task timeline")
        else:
            feedback_parts.append("File existed before task start (possible gaming)")
            
        if file_size > 30000:  # ~30KB minimum for a cylinder and skelion panel geometry
            score += 10
            feedback_parts.append(f"Acceptable model size ({file_size / 1024:.1f} KB)")
        else:
            feedback_parts.append(f"File unusually small ({file_size} bytes)")
    else:
        feedback_parts.append("Target file not saved")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    # Visual Process Verification via VLM
    if not query_vlm:
        return {"passed": False, "score": score, "feedback": "VLM not available. " + " | ".join(feedback_parts)}
        
    # Use trajectory frames to verify workflow + final clean state
    final_img = get_final_screenshot(traj)
    traj_frames = sample_trajectory_frames(traj, n=4)
    all_frames = traj_frames + [final_img] if final_img else traj_frames
    
    if not all_frames:
        feedback_parts.append("No screenshots available for VLM verification")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    prompt = """You are an expert SketchUp structural evaluator. Review these screenshots of the agent's workflow.
We need to determine if they successfully completed a circular solar infrastructure task.

Analyze the visual evidence and output a JSON object answering these true/false questions:
1. "cylinder_modeled": Is there a cylindrical 3D structure modeled in SketchUp?
2. "panels_placed": Are there solar panels (usually blue/dark rectangular components) placed on the top face of the cylinder?
3. "overhangs_cleaned": Look closely at the final layout. Did the agent delete the panels that hang over the edge of the circle? The array should be fully supported, with NO corners hanging off the circular lip into the air.

Respond strictly in JSON format:
{
    "cylinder_modeled": true/false,
    "panels_placed": true/false,
    "overhangs_cleaned": true/false,
    "reasoning": "brief explanation"
}
"""
    vlm_result = query_vlm(images=all_frames, prompt=prompt)
    
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("cylinder_modeled", False):
            score += 20
            feedback_parts.append("Cylinder modeled successfully")
            
        if parsed.get("panels_placed", False):
            score += 15
            feedback_parts.append("Panels placed on roof")
            
        if parsed.get("overhangs_cleaned", False):
            score += 30
            feedback_parts.append("Overhang cleanup verified")
        else:
            feedback_parts.append("Failed visual check: Overhanging panels present")
            
    else:
        feedback_parts.append(f"VLM evaluation error: {vlm_result.get('error', 'unknown')}")

    # To pass: must have file, modeled the cylinder, placed panels, and cleaned the overhangs
    key_criteria_met = output_exists and parsed.get("panels_placed", False) and parsed.get("overhangs_cleaned", False)
    passed = score >= 70 and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }