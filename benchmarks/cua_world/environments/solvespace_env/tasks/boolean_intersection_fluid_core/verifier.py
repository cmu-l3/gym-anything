#!/usr/bin/env python3
"""
Verifier for boolean_intersection_fluid_core task.

Multi-Criteria Evaluation:
1. File exists and was saved during the task (anti-gaming).
2. The agent explicitly used the Boolean Intersection mode (`meshCombine=2`).
3. 3D geometry matches the exact mathematical bounding box of a 10mm bicylinder (10x10x10).
4. 3D geometry matches the expected volume of a Steinmetz solid (~666.67 mm³).
5. VLM evaluation of the trajectory shows appropriate multi-plane sketch progression.
"""

import os
import json
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an agent using the CAD software SolveSpace. 
The agent's objective is to model the 3D fluid volume of a cross-junction (a bicylinder / Steinmetz solid).
To do this, the agent must:
1. Draw a cylinder on one plane.
2. Draw a second perpendicular cylinder on an intersecting plane.
3. Use a Boolean 'Intersection' operation to keep only the overlapping volume.

Look at these trajectory frames and the final state.
Do you see visual evidence that the agent attempted to create orthogonal intersecting cylindrical shapes?
A successful final result should look like a blocky core with curved faces, NOT a simple cube or sphere.

Respond with a JSON object containing:
{
    "attempted_orthogonal_cylinders": true/false,
    "reasoning": "brief explanation"
}"""

def verify_boolean_intersection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_vol = metadata.get('expected_volume', 666.67)
    vol_tol = metadata.get('volume_tolerance', 80.0)
    expected_bounds = metadata.get('expected_bounds', 10.0)
    bounds_tol = metadata.get('bounds_tolerance', 0.5)

    # 1. Get results from JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    used_intersection = result.get('intersection_mode_used', False)
    vol = result.get('stl_volume', 0.0)
    bx = result.get('bounds_x', 0.0)
    by = result.get('bounds_y', 0.0)
    bz = result.get('bounds_z', 0.0)

    # Basic File Checks (20 points total)
    if output_exists:
        score += 10
        feedback_parts.append("File exists")
    else:
        feedback_parts.append("File not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    if file_created:
        score += 10
        feedback_parts.append("File created during session")
    else:
        feedback_parts.append("Warning: File timestamp indicates it was not modified during task")

    # Semantic Check (20 points)
    if used_intersection:
        score += 20
        feedback_parts.append("Intersection mode detected")
    else:
        feedback_parts.append("Intersection mode not used")

    # Geometry Bounding Box (20 points)
    bounds_correct = (
        abs(bx - expected_bounds) <= bounds_tol and 
        abs(by - expected_bounds) <= bounds_tol and 
        abs(bz - expected_bounds) <= bounds_tol
    )
    if bounds_correct:
        score += 20
        feedback_parts.append(f"Bounds accurate ({bx:.1f}x{by:.1f}x{bz:.1f})")
    elif bx > 0 and by > 0 and bz > 0:
        feedback_parts.append(f"Bounds incorrect ({bx:.1f}x{by:.1f}x{bz:.1f})")
    else:
        feedback_parts.append("Could not extract bounds")

    # Geometry Volume Check (20 points)
    # A perfectly smooth bicylinder is ~666.67. SolveSpace meshes using piecewise linear faces.
    # Allowing [586.67, 746.67] rigorously isolates a bicylinder from a 10mm sphere (523) or 10mm cube (1000).
    volume_correct = abs(vol - expected_vol) <= vol_tol
    if volume_correct:
        score += 20
        feedback_parts.append(f"Volume accurate ({vol:.1f} mm³)")
    elif vol > 0:
        feedback_parts.append(f"Volume incorrect ({vol:.1f} mm³)")
    else:
        feedback_parts.append("Could not extract volume")

    # VLM Trajectory Verification (20 points)
    vlm_passed = False
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_img = get_final_screenshot(traj)
            if final_img:
                frames.append(final_img)
            
            vlm_response = query_vlm(prompt=VLM_PROMPT, images=frames)
            
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                vlm_passed = parsed.get("attempted_orthogonal_cylinders", False)
                if vlm_passed:
                    score += 20
                    feedback_parts.append("VLM visual confirmation passed")
                else:
                    feedback_parts.append("VLM did not observe correct CAD workflow")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback_parts.append("VLM check encountered an error")

    # Final Pass/Fail conditions
    key_criteria_met = file_created and used_intersection and volume_correct
    passed = (score >= 70) and key_criteria_met
    
    if passed:
        feedback_parts.insert(0, "SUCCESS")
    else:
        feedback_parts.insert(0, "FAILED")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }