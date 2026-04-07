#!/usr/bin/env python3
"""
Verifier for d_shaft_motor_hub task.
Uses a hybrid approach: programmatic file parsing of the .slvs text file 
combined with a VLM verification check of the trajectory.
"""

import json
import tempfile
import os
import re
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """
Analyze this sequence of screenshots from a CAD session (SolveSpace).
The user was tasked with creating a 3D cylindrical wheel hub adapter with a "D-shaft" mounting hole in the center.

Look at the final stages of the progression and the final view:
1. Is there a 3D cylindrical solid visible (not just a 2D sketch)?
2. Is there a through-hole in the center?
3. Does the through-hole have a D-shape? (i.e., a circle with one flat side, indicating the D-shaft profile).

Respond strictly with JSON format:
{
    "has_3d_cylinder": true/false,
    "has_center_hole": true/false,
    "hole_is_d_shaped": true/false,
    "reasoning": "brief explanation"
}
"""

def parse_slvs_parameters(content):
    """
    Parses a SolveSpace .slvs file to extract parameters, entity counts, and groups.
    """
    groups = re.findall(r'Group\.type=(\d+)', content)
    entities = re.findall(r'Entity\.type=(\d+)', content)
    
    # Extract all floating point parameter values
    param_vals = []
    for match in re.finditer(r'Param\.val=([-\d\.]+)', content):
        try:
            param_vals.append(float(match.group(1)))
        except ValueError:
            pass
            
    return {
        "extrude_groups": groups.count("5100"), # 5100 is EXTRUDE
        "line_entities": entities.count("11000"), # 11000 is line segment
        "arc_entities": entities.count("12000") + entities.count("13000"), # Arcs/circles
        "params": param_vals
    }

def verify_d_shaft_hub(traj, env_info, task_info):
    """Verifies the d-shaft hub geometry."""
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/SolveSpace/d_shaft_hub.slvs')
    
    score = 0
    feedback_parts = []
    
    # 1. Read JSON result
    result_json_path = "/tmp/task_result.json"
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_json_path, temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    output_exists = result.get("output_exists", False)
    file_created = result.get("file_created_during_task", False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Task failed: Output .slvs file was not found."}
    
    if not file_created:
        feedback_parts.append("Warning: File timestamp indicates it might not have been created during this task.")
    else:
        score += 15
        feedback_parts.append("File properly saved.")

    # 2. Read and parse the .slvs file
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    slvs_content = ""
    try:
        copy_from_env(expected_path, temp_slvs.name)
        with open(temp_slvs.name, 'r', encoding='utf-8', errors='ignore') as f:
            slvs_content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read .slvs file: {e}"}
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)

    slvs_data = parse_slvs_parameters(slvs_content)
    
    # Check extrusion group
    if slvs_data["extrude_groups"] > 0:
        score += 20
        feedback_parts.append("Extrude group created.")
    else:
        feedback_parts.append("Extrude group missing.")
        
    # Check D-profile topology (needs at least one line and one arc)
    if slvs_data["line_entities"] >= 1 and slvs_data["arc_entities"] >= 1:
        score += 15
        feedback_parts.append("D-profile lines/arcs drawn.")
    else:
        feedback_parts.append("Missing required line/arc geometry for the D-profile.")
        
    # Check parametric values (allowing radius or diameter depending on how it was constrained)
    params = slvs_data["params"]
    
    def has_param(val, tolerance=0.01):
        return any(abs(abs(p) - val) <= tolerance for p in params)
        
    has_od = has_param(20.0) or has_param(10.0) # Dia or Rad
    has_id = has_param(5.0) or has_param(2.5)   # Dia or Rad
    has_flat = has_param(2.0)
    has_extrude = has_param(10.0)
    
    if has_od and has_id and has_flat and has_extrude:
        score += 20
        feedback_parts.append("All parametric dimensions strictly correct.")
    else:
        missing = []
        if not has_od: missing.append("OD (20mm)")
        if not has_id: missing.append("ID (5mm)")
        if not has_flat: missing.append("Flat distance (2mm)")
        if not has_extrude: missing.append("Extrusion (10mm)")
        feedback_parts.append(f"Missing parameter constraints: {', '.join(missing)}")
        score += (4 - len(missing)) * 5  # Partial credit

    # 3. VLM Trajectory Verification
    vlm_success = False
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        vlm_resp = query_vlm(images=frames, prompt=VERIFICATION_PROMPT)
        if vlm_resp.get("success"):
            parsed = vlm_resp.get("parsed", {})
            if parsed.get("has_3d_cylinder") and parsed.get("has_center_hole") and parsed.get("hole_is_d_shaped"):
                score += 30
                vlm_success = True
                feedback_parts.append("VLM visual verification passed.")
            else:
                feedback_parts.append(f"VLM verification failed: {parsed.get('reasoning', 'Incorrect shape')}.")
        else:
            feedback_parts.append("VLM query failed or invalid JSON.")

    # Final scoring criteria
    passed = score >= 70 and slvs_data["extrude_groups"] > 0 and file_created and vlm_success

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }