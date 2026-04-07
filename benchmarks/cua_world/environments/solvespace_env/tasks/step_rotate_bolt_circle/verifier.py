#!/usr/bin/env python3
"""
Verifier for step_rotate_bolt_circle task.

VERIFICATION STRATEGY:
1. Programmatic: Check output file exists and was modified during task.
2. Programmatic: Parse the exported `.slvs` text file for correct group types (Extrude, Step Rotating).
3. Programmatic: Verify the Step Rotating group parameters (N=5 copies, Angle=60).
4. VLM: Check trajectory frames and final screenshot for visual evidence of the circular pattern.

Anti-gaming:
- File modification timestamp must be > task_start
- Trajectory frames are analyzed, not just the final screenshot.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating a 3D CAD task performed in SolveSpace.
The goal of the task is to create a circular array of 6 extruded cylindrical posts.

Look at the provided trajectory frames and the final screenshot of the SolveSpace application.
Analyze the progression and the final 3D viewport.

Please evaluate the following:
1. Is there a 3D model visible in the viewport?
2. Does the model contain extruded cylinder/post shapes?
3. Are the shapes arranged symmetrically in a circular pattern (a bolt-circle array)?
4. Does the visual progression in the frames show the user sketching, extruding, and applying a step rotation/pattern?

Provide your response strictly in the following JSON format:
{
    "has_3d_model": true/false,
    "has_cylinders": true/false,
    "is_circular_pattern": true/false,
    "shows_workflow": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of your observations"
}
"""

def verify_step_rotate_bolt_circle(traj, env_info, task_info):
    """Verify the step_rotate_bolt_circle task using programmatic and VLM signals."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_copies = metadata.get('expected_copies', 5)
    expected_angle = metadata.get('expected_angle', 60.0)
    angle_tolerance = metadata.get('angle_tolerance', 2.0)

    score = 0
    feedback_parts = []
    
    # 1. Read exported result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    output_exists = result.get('output_exists', False)
    file_modified = result.get('file_created_during_task', False)
    file_size = result.get('output_size_bytes', 0)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output .slvs file does not exist"}
    if not file_modified:
        return {"passed": False, "score": 0, "feedback": "File was not modified during task (anti-gaming)"}
    if file_size < 1000:
        return {"passed": False, "score": 0, "feedback": "File is too small to contain valid geometry"}

    score += 15
    feedback_parts.append("File exists and modified during task")

    # 2. Parse the .slvs file
    slvs_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    slvs_content = ""
    try:
        copy_from_env(result.get('output_path'), slvs_temp.name)
        with open(slvs_temp.name, 'r', encoding='utf-8', errors='ignore') as f:
            slvs_content = f.read()
    except Exception as e:
        logger.error(f"Failed to copy/read slvs file: {e}")
    finally:
        if os.path.exists(slvs_temp.name):
            os.unlink(slvs_temp.name)

    if not slvs_content:
        return {"passed": False, "score": score, "feedback": "Failed to read .slvs file content"}

    # Evaluate .slvs structures
    # SolveSpace groups are delimited by AddGroup directives
    groups = slvs_content.split("AddGroup")
    
    extrude_found = False
    step_rotating_found = False
    actual_n = None
    actual_a = None
    has_circle = False

    if "Request.type=400" in slvs_content or "Entity.type=12000" in slvs_content or "Entity.type=14000" in slvs_content:
        has_circle = True
        score += 5
        feedback_parts.append("Circle entity found")

    for g in groups:
        if "Group.type=5012" in g:
            extrude_found = True
            
        if "Group.type=5011" in g:
            step_rotating_found = True
            m_n = re.search(r'Group\.valN=(\d+)', g)
            if m_n:
                actual_n = int(m_n.group(1))
            m_a = re.search(r'Group\.valA=([-\d.]+)', g)
            if m_a:
                actual_a = float(m_a.group(1))

    if extrude_found:
        score += 15
        feedback_parts.append("Extrude group found")
    else:
        feedback_parts.append("Missing Extrude group")

    if step_rotating_found:
        score += 20
        feedback_parts.append("Step Rotating group found")
        
        # Check copies
        if actual_n == expected_copies:
            score += 10
            feedback_parts.append(f"Correct step count (N={expected_copies})")
        else:
            feedback_parts.append(f"Incorrect step count (found {actual_n}, expected {expected_copies})")
            
        # Check angle
        if actual_a is not None and abs(actual_a - expected_angle) <= angle_tolerance:
            score += 10
            feedback_parts.append(f"Correct step angle (≈{expected_angle}°)")
        else:
            feedback_parts.append(f"Incorrect step angle (found {actual_a}, expected ≈{expected_angle})")
    else:
        feedback_parts.append("Missing Step Rotating group")

    # 3. VLM Verification
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        # Make sure we have valid frames
        valid_frames = [f for f in frames + [final_img] if f is not None]
        
        if valid_frames:
            try:
                vlm_res = query_vlm(images=valid_frames, prompt=VLM_PROMPT)
                if vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    vlm_model = parsed.get("has_3d_model", False)
                    vlm_cyl = parsed.get("has_cylinders", False)
                    vlm_pattern = parsed.get("is_circular_pattern", False)
                    vlm_workflow = parsed.get("shows_workflow", False)
                    
                    vlm_score = 0
                    if vlm_model: vlm_score += 5
                    if vlm_cyl: vlm_score += 5
                    if vlm_pattern: vlm_score += 10
                    if vlm_workflow: vlm_score += 5
                    
                    score += vlm_score
                    if vlm_pattern:
                        feedback_parts.append("VLM confirmed circular 3D pattern")
                else:
                    feedback_parts.append(f"VLM error: {vlm_res.get('error')}")
            except Exception as e:
                logger.error(f"VLM Verification failed: {e}")
                feedback_parts.append("VLM verification exception")

    # Determine pass/fail
    # Requirements: File must exist, Score >= 60, Step Rotating must be used
    passed = (score >= 60) and output_exists and step_rotating_found and file_modified

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }