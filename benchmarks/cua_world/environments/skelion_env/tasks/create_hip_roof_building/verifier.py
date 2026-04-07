#!/usr/bin/env python3
"""
Verifier for create_hip_roof_building task in SketchUp.

Validates:
1. File exists, has content (>15KB), and was modified after task start.
2. Programmatic geometry matches expected 12x8x5.3 dimensions.
3. Model geometry contains exactly 4 pitched roof faces (hip roof).
4. VLM visual check confirms trajectory frames show a 3D house with a hip roof.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are evaluating a 3D modeling task in SketchUp.
The user was asked to create a residential building with a "hip roof". 
A hip roof has slopes on all four sides that meet at a ridge at the top. There should be NO flat vertical gables (triangles) on the ends.

Look at these screenshots (from the agent's workflow and final result).
Respond with a JSON object containing:
{
    "has_building": true/false,
    "has_hip_roof": true/false,
    "reasoning": "Brief explanation of the roof shape you see"
}
"""

def verify_create_hip_roof_building(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_w = metadata.get('expected_width_m', 12.0)
    expected_d = metadata.get('expected_depth_m', 8.0)
    expected_h = metadata.get('expected_height_m', 5.31)
    tolerance = metadata.get('tolerance_m', 1.5)
    min_size = metadata.get('min_file_size_bytes', 15000)

    # 1. Retrieve the exported JSON result from the container
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Docker paths generally support forward slashes even on Windows
        copy_from_env("C:/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    score = 0
    feedback_parts = []
    
    file_exists = result.get("file_exists", False)
    file_size = result.get("file_size_bytes", 0)
    created_during = result.get("file_created_during_task", False)
    geom = result.get("geometry", {})

    # Criterion 1: File Checks (25 points)
    if not file_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAIL: hip_roof_building.skp was not saved to Documents."
        }
    
    score += 10
    feedback_parts.append("File exists")

    if file_size > min_size:
        score += 5
    else:
        feedback_parts.append(f"Warning: File size ({file_size}b) is unusually small.")

    if created_during:
        score += 10
        feedback_parts.append("File created/modified during task")
    else:
        feedback_parts.append("Warning: File timestamp predates task (possible anti-gaming violation)")

    # Criterion 2: Geometry Dimensions (35 points)
    actual_w = geom.get("width_m", 0.0)
    actual_d = geom.get("depth_m", 0.0)
    actual_h = geom.get("height_m", 0.0)
    
    # Allow width/depth to be swapped (agent might draw 8x12 instead of 12x8)
    max_dim = max(actual_w, actual_d)
    min_dim = min(actual_w, actual_d)

    if abs(max_dim - expected_w) <= tolerance:
        score += 10
        feedback_parts.append("Width correct")
    else:
        feedback_parts.append(f"Width mismatch (got {max_dim:.1f}m)")

    if abs(min_dim - expected_d) <= tolerance:
        score += 10
        feedback_parts.append("Depth correct")
    else:
        feedback_parts.append(f"Depth mismatch (got {min_dim:.1f}m)")

    if abs(actual_h - expected_h) <= tolerance:
        score += 15
        feedback_parts.append("Height correct")
    else:
        feedback_parts.append(f"Height mismatch (got {actual_h:.1f}m)")

    # Criterion 3: Roof Topology (25 points)
    total_faces = geom.get("total_faces", 0)
    roof_faces = geom.get("roof_slope_faces", 0)

    if total_faces >= 9:
        score += 5
    
    if roof_faces == 4:
        score += 20
        feedback_parts.append("Hip roof geometry detected (4 pitched faces)")
    elif roof_faces > 0:
        feedback_parts.append(f"Incorrect roof topology: {roof_faces} pitched faces (expected 4)")
    else:
        feedback_parts.append("No pitched roof faces detected")

    # Criterion 4: VLM Visual Verification (15 points)
    query_vlm = env_info.get('query_vlm')
    has_hip_roof = False
    
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            try:
                vlm_res = query_vlm(images=images, prompt=VERIFICATION_PROMPT)
                parsed = vlm_res.get("parsed", {})
                has_building = parsed.get("has_building", False)
                has_hip_roof = parsed.get("has_hip_roof", False)
                
                if has_hip_roof:
                    score += 15
                    feedback_parts.append("VLM visually confirmed hip roof")
                elif has_building:
                    feedback_parts.append("VLM saw building, but no hip roof")
                else:
                    feedback_parts.append("VLM did not detect a building")
            except Exception as e:
                logger.error(f"VLM check failed: {e}")
                feedback_parts.append("VLM check encountered an error")

    # Final Evaluation
    key_criteria_met = file_exists and (roof_faces == 4 or has_hip_roof)
    passed = (score >= 65) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }