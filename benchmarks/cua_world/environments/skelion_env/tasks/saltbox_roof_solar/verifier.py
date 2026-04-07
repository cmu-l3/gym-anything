#!/usr/bin/env python3
"""
Verifier for Saltbox Roof Solar Installation task.

Evaluates multi-modal criteria:
1. File verification: Did the agent save a SketchUp file after the task started? (Anti-gaming)
2. Trajectory VLM verification: Did the agent model the asymmetric saltbox roof?
3. Trajectory VLM verification: Were panels applied to the correct roof using Skelion?
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating a SketchUp 3D modeling task involving a solar panel installation on a saltbox-style roof.
Please review the provided trajectory screenshots and the final state carefully.

Task Requirements:
1. Building Geometry: A saltbox roof building (one wall significantly taller than the opposite wall, creating an asymmetric, single long slope).
2. Solar Panels: Dark blue/black rectangular panels placed on the long (south-facing) roof slope.
3. Panel Orientation: Panels must be flush-mounted (0 degree tilt, lying flat on the roof surface) and in landscape orientation (wider than they are tall).
4. Skelion Usage: The user should have used the Skelion plugin dialog to configure and place the panels.
5. Location Configuration: The user should have accessed the Geo-location or Skelion location dialog to set the model location.

Evaluate and return a JSON object with the following boolean fields:
{
    "has_saltbox_roof": true/false,
    "panels_on_roof": true/false,
    "panels_flush_mounted": true/false,
    "panels_landscape_orientation": true/false,
    "used_skelion_plugin": true/false,
    "location_set_in_trajectory": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_saltbox_solar(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_size = metadata.get('min_file_size_bytes', 50000)
    
    # 1. Gather programmatic state (exported from Windows container)
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Check standard Linux mapping path
        copied = False
        for path in ["/tmp/task_result.json", "C:\\tmp\\task_result.json"]:
            try:
                copy_from_env(path, temp_file.name)
                with open(temp_file.name, 'r') as f:
                    result = json.load(f)
                copied = True
                break
            except Exception:
                continue
                
        if not copied:
            return {"passed": False, "score": 0, "feedback": "Failed to read task result from environment."}
            
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    output_exists = result.get("output_exists", False)
    file_created = result.get("file_created_during_task", False)
    file_size = result.get("output_size_bytes", 0)
    
    if output_exists:
        if file_created:
            score += 10
            feedback.append("File created correctly.")
        else:
            feedback.append("File exists but predates task start (Anti-gaming failed).")
            
        if file_size > min_size:
            score += 5
            feedback.append(f"File size acceptable ({file_size} bytes).")
        else:
            feedback.append(f"File size too small ({file_size} bytes).")
    else:
        feedback.append("Expected SketchUp file was not saved.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # 2. Visually verify process and final state using Trajectory
    if not query_vlm:
        feedback.append("VLM not available for visual verification.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}
        
    frames = sample_trajectory_frames(traj, n=5)
    final = get_final_screenshot(traj)
    images = frames + [final] if final else frames
    
    if not images:
        feedback.append("No screenshots available for VLM.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}
        
    vlm_result = query_vlm(prompt=VLM_PROMPT, images=images)
    
    if not vlm_result.get("success"):
        feedback.append("VLM verification failed to process.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}
        
    parsed = vlm_result.get("parsed", {})
    
    has_saltbox = parsed.get("has_saltbox_roof", False)
    panels_on_roof = parsed.get("panels_on_roof", False)
    panels_flush = parsed.get("panels_flush_mounted", False)
    landscape = parsed.get("panels_landscape_orientation", False)
    used_skelion = parsed.get("used_skelion_plugin", False)
    location_set = parsed.get("location_set_in_trajectory", False)
    
    # 3. Apply Trajectory and Output Checks
    if has_saltbox:
        score += 20
        feedback.append("Saltbox roof verified.")
    else:
        feedback.append("Saltbox roof not detected.")
        
    if panels_on_roof:
        score += 25
        feedback.append("Panels on roof verified.")
    else:
        feedback.append("Panels not detected on roof.")
        
    if panels_flush and landscape:
        score += 15
        feedback.append("Panels flush & landscape verified.")
    else:
        feedback.append("Panel orientation/tilt incorrect.")
        
    if used_skelion:
        score += 15
        feedback.append("Skelion usage verified.")
    else:
        feedback.append("Skelion plugin usage not visible.")

    if location_set:
        score += 10
        feedback.append("Location configuration verified.")
    else:
        feedback.append("Location configuration not visible.")

    # Threshold for success requires the file to exist AND core modeling visually validated
    passed = (score >= 65 and output_exists and has_saltbox and panels_on_roof)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": parsed
    }