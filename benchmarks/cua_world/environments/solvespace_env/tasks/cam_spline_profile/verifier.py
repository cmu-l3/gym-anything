#!/usr/bin/env python3
"""
Verifier for cam_spline_profile task.

Hybrid programmatic + VLM Verification Strategy:
1. File Checks (Programmatic): 
   - File exists at expected path & modified during task (anti-gaming)
   - Parse SLVS text for Request/Entity types mapping to Cubic Splines
   - Parse SLVS text for Extrusion group existence
2. Visual/Trajectory Checks (VLM):
   - Confirms the agent's trajectory actually shows the spline tool being used
   - Confirms the final result is a smooth curved shape (not a polygon)
   - Confirms the presence of a 3D solid rendering.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an agent's completion of a 3D CAD modeling task in SolveSpace.

TASK REQUIREMENTS:
1. The agent must draw a 2D smooth, curved cam profile using the "Cubic Spline" tool. It must NOT be a polygon made of straight lines, and it must NOT just be a simple circle.
2. The agent must close the spline into a loop.
3. The agent must extrude the 2D sketch into a 3D solid plate.

Analyze the provided screenshots (trajectory sequence and final result) and respond with a JSON object containing:
{
    "spline_tool_used": boolean, (Did you see evidence of a curved spline/points being drawn or the spline tool active?)
    "smooth_closed_shape": boolean, (Is the final shape a smooth closed loop with no sharp polygonal corners?)
    "is_3d_extruded": boolean, (Is there a visible 3D solid / thickness to the shape, rather than just a flat 2D sketch?)
    "confidence": "low" | "medium" | "high",
    "reasoning": "string explaining your observations"
}
"""

def verify_cam_spline_profile(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Error: copy_from_env not available"}

    feedback_parts = []
    score = 0

    # 1. Retrieve and analyze programmatic results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic file presence & anti-gaming
    if result.get("file_exists") and result.get("file_modified_after_start"):
        score += 15
        feedback_parts.append("File correctly saved")
    else:
        feedback_parts.append("File not found or not created during task")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    if result.get("file_size_bytes", 0) > 200:
        score += 5

    # SLVS Content Programmatic Analysis
    has_spline = result.get("has_cubic_spline", False)
    if has_spline:
        score += 20
        feedback_parts.append("Cubic Spline entity verified in file")
    else:
        feedback_parts.append("No Cubic Spline found in saved file")

    points_count = result.get("spline_points_count", 0)
    if points_count >= 6:
        score += 10
        feedback_parts.append(f"Sufficient control points ({points_count})")
    elif points_count > 0:
        score += 5
        feedback_parts.append(f"Insufficient control points ({points_count} < 6)")

    has_extrusion = result.get("has_extrusion_group", False)
    if has_extrusion:
        score += 10
        feedback_parts.append("Extrusion group verified in file")
    else:
        feedback_parts.append("No extrusion group found in file")

    # 2. VLM Trajectory Verification
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            vlm_response = query_vlm(
                prompt=VLM_PROMPT,
                images=images
            )
            
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                
                if parsed.get("spline_tool_used", False):
                    vlm_score += 10
                    feedback_parts.append("VLM: Spline tool used")
                
                if parsed.get("smooth_closed_shape", False):
                    vlm_score += 15
                    feedback_parts.append("VLM: Smooth closed shape confirmed")
                else:
                    feedback_parts.append("VLM: Shape is not a smooth closed curve")
                    
                if parsed.get("is_3d_extruded", False):
                    vlm_score += 15
                    feedback_parts.append("VLM: 3D extrusion confirmed")
                else:
                    feedback_parts.append("VLM: Extrusion missing visually")
            else:
                feedback_parts.append(f"VLM error: {vlm_response.get('error')}")
        else:
            feedback_parts.append("No screenshots available for VLM")
    else:
        feedback_parts.append("VLM function unavailable")

    score += vlm_score

    # Passing criteria: Minimum 60 points + file must have spline & extrusion
    key_criteria_met = has_spline and has_extrusion and result.get("file_exists")
    passed = score >= 60 and key_criteria_met

    if not passed and score >= 60:
        feedback_parts.append("FAILED: Missing core required geometries (Spline/Extrusion) programmatically.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }