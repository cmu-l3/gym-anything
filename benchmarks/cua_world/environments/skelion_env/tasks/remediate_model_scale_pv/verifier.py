#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_remediate_model_scale_pv(traj, env_info, task_info):
    """
    Verify the model scale remediation and panel placement using a multi-signal approach.
    1. Validates output file modification timestamps.
    2. Uses VLM trajectory analysis to ensure panels were placed.
    3. Uses VLM to check scale implicitly: 10x scale results in visually microscopic panels, 
       while proper scale results in panels taking up normal residential roof proportions.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}
        
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # CRITERIA 1: Check basic file conditions
    output_exists = result.get('output_exists', False)
    file_modified = result.get('file_modified', False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output file scaled_solar_design.skp not found"}
        
    score = 20 # 20 points for saving the file
    feedback_parts = ["File saved successfully"]
    
    # CRITERIA 2 & 3: VLM Verification of Placement and Proportions
    if not query_vlm:
        return {"passed": False, "score": score, "feedback": "query_vlm not available for visual verification"}
        
    # Use trajectory frames to capture work context, not just the final screenshot
    frames = sample_trajectory_frames(traj, n=3)
    final = get_final_screenshot(traj)
    images = frames + [final] if final else frames
    
    if not images:
        return {"passed": False, "score": score, "feedback": "No screenshots available for VLM verification"}
    
    prompt = """You are evaluating a solar PV design task in SketchUp where the agent had to fix a 10x scaled-up model and then place solar panels.

Task requirements:
1. The agent must correct the scale of the house (it started 10x too big).
2. The agent must place solar panels on the south-facing roof using Skelion.

To verify the scale is correct: Look at the size of the solar panels relative to the roof. Standard panels are about 1.6m x 1m. On a normal residential roof, you might fit 2-4 rows of panels. If the roof is covered in TINY panels (like a grid of 20+ rows of tiny tiles), the scale was NOT fixed (the house is still 10x too big). If the panels look like normal-sized panels covering the roof reasonably, the scale was fixed.

To verify panel placement: Blue/dark solar panel models should be visibly attached to the roof.

Respond in JSON format exactly like this:
{
    "panels_placed": true/false,
    "scale_looks_corrected": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Explain your observations about the panel size relative to the roof"
}"""

    vlm_result = query_vlm(images=images, prompt=prompt)
    
    if not vlm_result.get("success"):
        return {"passed": False, "score": score, "feedback": f"VLM error: {vlm_result.get('error')}"}
        
    parsed = vlm_result.get("parsed", {})
    panels_placed = parsed.get("panels_placed", False)
    scale_corrected = parsed.get("scale_looks_corrected", False)
    
    if panels_placed:
        score += 30
        feedback_parts.append("Panels successfully placed")
    else:
        feedback_parts.append("Panels NOT placed")
        
    if scale_corrected:
        score += 50
        feedback_parts.append("Scale verified as corrected")
    else:
        feedback_parts.append("Scale NOT corrected (panels appear far too small)")
        
    passed = panels_placed and scale_corrected and output_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }