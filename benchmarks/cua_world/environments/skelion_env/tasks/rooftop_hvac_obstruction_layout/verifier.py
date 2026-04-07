#!/usr/bin/env python3
"""
Verifier for rooftop_hvac_obstruction_layout task.
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM prompt to check 3D geometry and Skelion usage
VLM_PROMPT = """You are an expert at evaluating SketchUp models and solar PV design.
The user was asked to:
1. Model a flat-roofed rectangular building (approx 40x30 ft footprint, 12 ft tall).
2. Model a square HVAC unit obstruction (approx 6x6 ft footprint, 4 ft tall) centered on the roof.
3. Use Skelion to place south-facing, landscape-oriented solar panels with a 10-degree tilt on the roof.
4. Avoid placing panels on or overlapping the HVAC unit.

Please analyze these screenshots from their workflow. Pay special attention to the later/final frames showing the 3D model.

Determine the following:
1. building_visible: Is there a 3D rectangular building with a flat roof visible?
2. hvac_visible: Is there a smaller raised box (HVAC unit) visible on the roof?
3. panels_visible: Are there blue/dark rectangular solar panels placed on the roof?
4. panels_landscape: Are the panels in landscape orientation (wider than they are tall)?
5. obstruction_avoided: Is there a clear gap/keepout zone where panels do NOT overlap or intersect with the HVAC unit?
6. good_coverage: Are panels placed on multiple sides of the HVAC unit (e.g., in front and behind it), utilizing the available space properly rather than just one tiny patch?

Respond with ONLY a JSON object:
{
    "building_visible": true/false,
    "hvac_visible": true/false,
    "panels_visible": true/false,
    "panels_landscape": true/false,
    "obstruction_avoided": true/false,
    "good_coverage": true/false,
    "reasoning": "Brief explanation of what you see"
}
"""

def verify_rooftop_hvac_obstruction_layout(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the rooftop HVAC obstruction layout task.
    Combines file timestamp/size verification (anti-gaming) with multi-frame VLM spatial evaluation.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    if not query_vlm:
        return {"passed": False, "score": 0, "feedback": "VLM query function not available"}

    metadata = task_info.get('metadata', {})
    min_size_bytes = metadata.get('min_file_size_bytes', 20000)

    score = 0
    feedback_parts = []
    
    # 1. Read exported result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # File path must match what is written by export_result.ps1
        copy_from_env("C:\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result from container: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Programmatic checks (File existence, size, timestamp)
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    file_size_bytes = result.get('output_size_bytes', 0)
    
    if output_exists:
        if file_created_during_task:
            score += 15
            feedback_parts.append("File modified during task (+15)")
        else:
            feedback_parts.append("File exists but was NOT modified during task (possible cheat)")
            
        if file_size_bytes >= min_size_bytes:
            score += 10
            feedback_parts.append(f"File size OK: {file_size_bytes} bytes (+10)")
        else:
            feedback_parts.append(f"File size too small: {file_size_bytes} bytes")
    else:
        feedback_parts.append("Output .skp file not found")
        # Early exit if the user didn't even save the file
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. VLM Trajectory Verification
    # We use multiple frames because the final frame might be obscured by a menu
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    images = frames + [final] if final else frames

    if not images:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " | No images available for VLM"}

    vlm_resp = query_vlm(
        images=images,
        prompt=VLM_PROMPT
    )

    if not vlm_resp.get("success"):
        return {"passed": False, "score": score, "feedback": f"VLM error: {vlm_resp.get('error')}"}

    parsed = vlm_resp.get("parsed", {})
    
    building = parsed.get("building_visible", False)
    hvac = parsed.get("hvac_visible", False)
    panels = parsed.get("panels_visible", False)
    landscape = parsed.get("panels_landscape", False)
    avoided = parsed.get("obstruction_avoided", False)
    coverage = parsed.get("good_coverage", False)

    # Add points based on VLM findings
    if building:
        score += 15
        feedback_parts.append("Building visible (+15)")
    else:
        feedback_parts.append("Building not visible")

    if hvac:
        score += 15
        feedback_parts.append("HVAC unit visible (+15)")
    else:
        feedback_parts.append("HVAC unit not visible")

    if panels:
        score += 15
        feedback_parts.append("Solar panels visible (+15)")
    else:
        feedback_parts.append("Solar panels not visible")

    if landscape:
        score += 5
        feedback_parts.append("Landscape panels confirmed (+5)")
        
    if avoided:
        score += 15
        feedback_parts.append("Obstruction avoided successfully (+15)")
    else:
        feedback_parts.append("Obstruction NOT avoided (panels intersect)")

    if coverage:
        score += 10
        feedback_parts.append("Good roof coverage (+10)")

    # 4. Final Verification Logic
    # Agent MUST have saved the file, created the building, placed panels, AND avoided the obstruction
    key_criteria_met = output_exists and file_created_during_task and building and panels and avoided
    
    passed = score >= 60 and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": parsed
    }