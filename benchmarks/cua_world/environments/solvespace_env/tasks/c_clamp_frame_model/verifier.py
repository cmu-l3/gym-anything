#!/usr/bin/env python3
"""
Verifier for the C-Clamp Frame Model task.

Checks:
1. File exists and was created during the task
2. File contents contain structural evidence of correct SolveSpace usage:
   - Multiple extrusions (base + hole)
   - Boolean Difference operation for the hole
   - Arcs and lines in the sketch
   - Correct dimensional constraints (R50, R30, D10, Extrude 15)
3. VLM verification on trajectory frames to ensure the 3D model looks correct.
"""

import json
import os
import re
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying a 3D CAD modeling task.
The agent was asked to model a parametric 3D C-clamp frame in SolveSpace.

REQUIREMENTS:
1. It should look like a C-clamp frame (a solid 'C' shaped profile).
2. It must be a 3D extruded solid, not just a flat 2D sketch.
3. It must have a functional hole cut vertically through the top arm (for a threaded rod).

Examine the trajectory and final image. 
- Did the agent successfully extrude a C-shaped solid?
- Is there a visible hole passing through the top arm?

Return JSON format exactly like this:
{
  "is_c_shape": true/false,
  "is_3d_extruded": true/false,
  "has_hole": true/false,
  "confidence": "high/medium/low",
  "reasoning": "Brief explanation of what is visible"
}
"""

def verify_c_clamp_frame(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Read task execution results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    file_exists = result.get("file_exists", False)
    created_during_task = result.get("file_created_during_task", False)
    
    if not file_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed: c_clamp_frame.slvs was not found. Agent did not save the file."
        }
    if not created_during_task:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed: c_clamp_frame.slvs was modified before the task started (anti-gaming check)."
        }

    score += 15
    feedback_parts.append("File exists and created during task (+15)")

    # 2. Parse the SolveSpace file
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    slvs_content = ""
    try:
        copy_from_env("/home/ga/Documents/SolveSpace/c_clamp_frame.slvs", temp_slvs.name)
        with open(temp_slvs.name, 'r', encoding='utf-8', errors='ignore') as f:
            slvs_content = f.read()
    except Exception as e:
        logger.warning(f"Could not read .slvs file: {e}")
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)

    # 3. Structural checks on the SLVS text format
    extrude_groups = len(re.findall(r'Group\.type=5100', slvs_content))
    diff_groups = len(re.findall(r'meshCombine=1', slvs_content))
    
    has_arcs = bool(re.search(r'Entity\.type=150', slvs_content) or re.search(r'Entity\.type=130', slvs_content))
    has_lines = bool(re.search(r'Entity\.type=11000', slvs_content))
    
    # Check for requested constraints (val format in SolveSpace usually contains the exact digits padded with zeros)
    has_r50 = bool(re.search(r'val=-?50\.0', slvs_content))
    has_r30 = bool(re.search(r'val=-?30\.0', slvs_content))
    has_hole_dim = bool(re.search(r'val=-?5\.0', slvs_content)) or bool(re.search(r'val=-?10\.0', slvs_content))
    has_extrude_15 = bool(re.search(r'val=-?15\.0', slvs_content))

    if extrude_groups >= 1:
        score += 10
        feedback_parts.append("Base extrusion found (+10)")
        if has_extrude_15:
            score += 5
            feedback_parts.append("15mm extrusion depth found (+5)")
            
    if diff_groups >= 1:
        score += 15
        feedback_parts.append("Boolean difference found (+15)")

    if has_arcs and has_lines:
        score += 10
        feedback_parts.append("Profile geometry (arcs/lines) found (+10)")
        
    if has_r50 and has_r30:
        score += 10
        feedback_parts.append("Outer/Inner arc radii found (+10)")
        
    if has_hole_dim:
        score += 5
        feedback_parts.append("Hole diameter/radius found (+5)")

    # 4. VLM Verification
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        images = frames + [final_img] if final_img else frames
        
        if images:
            vlm_response = query_vlm(images=images, prompt=VLM_PROMPT)
            parsed = vlm_response.get("parsed", {})
            
            is_c_shape = parsed.get("is_c_shape", False)
            is_3d = parsed.get("is_3d_extruded", False)
            has_hole = parsed.get("has_hole", False)
            
            vlm_score = 0
            if is_c_shape:
                vlm_score += 10
            if is_3d:
                vlm_score += 10
            if has_hole:
                vlm_score += 10
                
            score += vlm_score
            if vlm_score > 0:
                feedback_parts.append(f"VLM verified visuals (+{vlm_score}): shape={is_c_shape}, 3D={is_3d}, hole={has_hole}")
            else:
                feedback_parts.append("VLM did not verify visual requirements.")
        else:
            feedback_parts.append("No images available for VLM verification.")
    else:
        feedback_parts.append("VLM query function unavailable.")

    # Determine final pass status
    # Key criteria: Must have saved the file, extruded it, and applied boolean difference or passed visual hole check
    key_criteria_met = file_exists and created_during_task and (extrude_groups >= 1) and (diff_groups >= 1 or score >= 70)
    passed = score >= 65 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }