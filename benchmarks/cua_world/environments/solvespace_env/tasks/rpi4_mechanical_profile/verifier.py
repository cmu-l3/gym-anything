#!/usr/bin/env python3
"""
Verifier for rpi4_mechanical_profile task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are verifying if a computer agent successfully created a 3D CAD model of a Raspberry Pi 4 board in SolveSpace.

Please review these screenshots from the agent's session and the final result.

Determine:
1. Did the agent use the SolveSpace UI to draw a rectangle and circles?
2. Did the agent apply dimensional constraints?
3. Is there a 3D extruded view showing a rectangular board with 4 holes near the corners?

Respond EXACTLY in this JSON format:
{
    "used_ui_to_draw": true/false,
    "applied_constraints": true/false,
    "extruded_3d_board_with_holes_visible": true/false,
    "reasoning": "Brief explanation"
}
"""

def verify_rpi4_profile(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/SolveSpace/rpi4_mockup.slvs')
    
    score = 0
    feedback_parts = []
    
    # Read task result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output file rpi4_mockup.slvs was not created."}
    
    if not file_created:
        feedback_parts.append("File exists but was not created during task (anti-gaming).")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}
    
    score += 10
    feedback_parts.append("File created successfully.")
    
    # Read the SLVS file to check contents
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    try:
        copy_from_env(expected_output_path, temp_slvs.name)
        with open(temp_slvs.name, 'r') as f:
            slvs_content = f.read()
    except Exception as e:
        slvs_content = ""
        feedback_parts.append(f"Could not read .slvs file: {e}")
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)
            
    # Parse Param.val from SLVS (robust method regardless of exact internal group IDs)
    param_vals = []
    has_circles = False
    
    for line in slvs_content.split('\n'):
        if 'Param.val=' in line:
            try:
                val = float(line.split('=')[1].strip())
                param_vals.append(val)
            except:
                pass
        if 'Request.type=300' in line or 'Request.type=400' in line:
            has_circles = True
            
    # Check for expected dimensions within tolerance
    def has_val(target, tol=0.01):
        return any(abs(v - target) <= tol for v in param_vals)
    
    # Outer Boundary (20 pts)
    if has_val(85.0) and has_val(56.0):
        score += 20
        feedback_parts.append("Outer boundary dimensions found (85x56).")
    elif has_val(85.0) or has_val(56.0):
        score += 10
        feedback_parts.append("Partial outer boundary dimensions found.")
    else:
        feedback_parts.append("Outer boundary dimensions missing.")

    # Hole Entities (10 pts)
    if has_circles:
        score += 10
        feedback_parts.append("Circle entities found.")
    else:
        feedback_parts.append("No circle entities found.")
        
    # Hole Sizing (10 pts)
    if has_val(2.75) or has_val(1.375):
        score += 10
        feedback_parts.append("Hole sizing constraints found (2.75 / 1.375).")
    else:
        feedback_parts.append("Hole sizing constraints missing.")
        
    # Hole Placement (20 pts)
    placement_score = 0
    if has_val(58.0): placement_score += 8
    if has_val(49.0): placement_score += 8
    if has_val(3.5): placement_score += 4
    score += placement_score
    if placement_score == 20:
        feedback_parts.append("All hole placement constraints found.")
    else:
        feedback_parts.append("Some hole placement constraints missing.")
        
    # Extrusion Depth (10 pts)
    if has_val(1.6):
        score += 10
        feedback_parts.append("Extrusion depth parameter found (1.6).")
    else:
        feedback_parts.append("Extrusion depth missing.")

    # VLM Verification (20 pts)
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            vlm_result = query_vlm(
                prompt=VERIFICATION_PROMPT,
                images=images
            )
            
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("used_ui_to_draw"):
                    score += 5
                if parsed.get("applied_constraints"):
                    score += 5
                if parsed.get("extruded_3d_board_with_holes_visible"):
                    score += 10
                    feedback_parts.append("VLM confirmed 3D extruded board with holes.")
                else:
                    feedback_parts.append("VLM did not clearly see the final 3D board.")
            else:
                feedback_parts.append("VLM query failed, skipping visual check.")
    else:
        feedback_parts.append("VLM not available, skipping visual check.")

    passed = score >= 75 and (has_val(85.0) or has_val(56.0)) and (has_val(58.0) or has_val(49.0))
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }