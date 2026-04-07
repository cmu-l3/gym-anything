#!/usr/bin/env python3
"""
Verifier for the dovetail_guide_profile task.

Verification Strategy:
1. Programmatic Checks (via .slvs file parsing):
   - File exists and was created during the task
   - Contains >= 8 line segments (Entity.type=11000)
   - Contains an extrude group (Group.type=5100)
   - Contains the exact expected parameters for constraints (50, 30, 10, 25/15, 80)
2. Visual Checks (via VLM and Trajectory):
   - Identifies the characteristic extruded dovetail shape
   - Proves workflow progression
"""

import os
import json
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating a CAD modeling task in SolveSpace.
The goal was to create a 3D extruded "dovetail guide rail".
A dovetail profile looks like a rectangular base with a centered trapezoid (wider at the top, narrower at the base) sitting on top of it.

Look closely at these trajectory screenshots and the final state.
1. Did the user successfully sketch a closed dovetail profile (8-sided polygon)?
2. Did the user extrude this sketch into a 3D shape?
3. In the final view, do you see a 3D solid that matches this dovetail description?

Respond strictly in this JSON format:
{
    "sketch_visible": true/false,
    "extrusion_visible": true/false,
    "dovetail_shape_correct": true/false,
    "reasoning": "Brief explanation of what you see"
}
"""

def verify_dovetail_profile(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Extract metadata
    metadata = task_info.get('metadata', {})
    
    # 1. Fetch JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Base Validation
    output_exists = result.get('output_exists', False)
    created_during_task = result.get('file_created_during_task', False)

    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output file dovetail_rail.slvs was not created."}
    
    if not created_during_task:
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not created/modified during the task (gaming detected)."}

    score += 15
    feedback_parts.append("File created")

    # 3. Parse .slvs file contents
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    try:
        copy_from_env("/tmp/dovetail_rail.slvs", temp_slvs.name)
        with open(temp_slvs.name, 'r', encoding='utf-8', errors='ignore') as f:
            slvs_content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": "Failed to read .slvs file"}
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)

    # Check for line segments
    line_count = slvs_content.count("Entity.type=11000")
    if line_count >= 8:
        score += 15
        feedback_parts.append(f"Contains {line_count} line segments")
    else:
        feedback_parts.append(f"Only {line_count} line segments found (expected at least 8)")

    # Check for extrusion group
    has_extrusion = "Group.type=5100" in slvs_content
    if has_extrusion:
        score += 10
        feedback_parts.append("Extrusion group found")
    else:
        feedback_parts.append("No extrusion group found")

    # Extract all parameters to check dimensions
    # SolveSpace saves params like: Param.val=50.000000000000000000
    param_matches = re.findall(r'Param\.val=([-\d\.]+)', slvs_content)
    params = []
    for p in param_matches:
        try:
            params.append(float(p))
        except ValueError:
            pass
            
    def check_param(expected_val, tolerance=0.1):
        for p in params:
            if abs(p - expected_val) <= tolerance:
                return True
        return False

    # Check dimensions
    dims_found = 0
    if check_param(50.0): dims_found += 1
    if check_param(30.0): dims_found += 1
    if check_param(10.0): dims_found += 1
    if check_param(25.0) or check_param(15.0): dims_found += 1
    if check_param(80.0): dims_found += 1

    score += (dims_found * 6) # Up to 30 points
    feedback_parts.append(f"Found {dims_found}/5 expected dimension values")

    # 4. VLM Verification
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            
            if final:
                vlm_result = query_vlm(
                    images=frames + [final],
                    prompt=VLM_PROMPT
                )
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("sketch_visible"): score += 10
                    if parsed.get("extrusion_visible"): score += 10
                    if parsed.get("dovetail_shape_correct"): score += 10
                    
                    feedback_parts.append(f"VLM: {parsed.get('reasoning', 'Verified')}")
                else:
                    feedback_parts.append("VLM verification failed to parse")
            else:
                feedback_parts.append("No screenshots available for VLM")
        except Exception as e:
            logger.error(f"VLM evaluation error: {e}")
            feedback_parts.append("VLM evaluation error")

    # Calculate final pass
    # Must achieve at least 70 points AND have the extrusion & line count
    key_criteria_met = (line_count >= 8) and has_extrusion and (dims_found >= 3)
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }