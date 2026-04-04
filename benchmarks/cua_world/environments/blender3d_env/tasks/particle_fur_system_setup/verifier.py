#!/usr/bin/env python3
import json
import os
import logging
from typing import Any

logger = logging.getLogger(__name__)

def verify_particle_fur_system_setup(
    traj: list[dict],
    env_info: dict,
    task_info: dict,
) -> dict:
    """
    Verify the particle_fur_system_setup task.
    
    Scores 7 criteria for 100 total points.
    Pass threshold: 70 points.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "score": 0, 
            "passed": False, 
            "feedback": "Framework error: copy_from_env not available"
        }

    score = 0
    max_score = 100
    details = {}
    feedback_parts = []
    
    # Copy result file from environment
    result_path = "/tmp/verifier_task_result.json"
    result_data = {}
    
    try:
        # Clean up previous run
        if os.path.exists(result_path):
            os.unlink(result_path)
            
        copy_from_env("/tmp/task_result.json", result_path)
        
        if os.path.exists(result_path):
            with open(result_path, 'r') as f:
                result_data = json.load(f)
        else:
            return {
                "score": 0,
                "passed": False,
                "feedback": "Task result file not found - export may have failed"
            }
    except Exception as e:
        return {
            "score": 0,
            "passed": False,
            "feedback": f"Failed to load verification results: {str(e)}"
        }
    finally:
        # Cleanup
        if os.path.exists(result_path):
            os.unlink(result_path)
    
    scene = result_data.get("scene_analysis", {})
    blend_info = result_data.get("blend_file", {})
    render_info = result_data.get("render_file", {})
    
    # ================================================================
    # Criterion 1: Suzanne mesh present (15 points)
    # ================================================================
    suzanne_score = 0
    suzanne_found = scene.get("suzanne_found", False)
    suzanne_verts = scene.get("suzanne_vertex_count", 0)
    
    if suzanne_found and suzanne_verts >= 400:
        suzanne_score = 15
        feedback_parts.append(f"Suzanne mesh found ({suzanne_verts} verts)")
    elif suzanne_found:
        suzanne_score = 5
        feedback_parts.append(f"Suzanne found but low vertex count ({suzanne_verts})")
    else:
        feedback_parts.append("No Suzanne/Monkey mesh found")
    score += suzanne_score
    
    # ================================================================
    # Criterion 2: Hair particle system exists (20 points)
    # ================================================================
    hair_score = 0
    hair_found = scene.get("hair_system_found", False)
    total_ps = scene.get("total_particle_systems", 0)
    
    if hair_found:
        hair_score = 20
        feedback_parts.append("Hair particle system found")
    elif total_ps > 0:
        hair_score = 5
        feedback_parts.append("Particle system found but wrong type (not HAIR)")
    else:
        feedback_parts.append("No particle systems found")
    score += hair_score
    
    # ================================================================
    # Criterion 3: Hair count and length (15 points)
    # ================================================================
    params_score = 0
    hair_count = scene.get("hair_count", 0)
    hair_length = scene.get("hair_length", 0.0)
    
    count_ok = hair_count >= 5000
    length_ok = 0.05 <= hair_length <= 0.30
    
    if count_ok and length_ok:
        params_score = 15
        feedback_parts.append(f"Hair params OK (count={hair_count}, len={hair_length})")
    elif count_ok or length_ok:
        params_score = 8
        feedback_parts.append(f"Hair params partial (count={hair_count}, len={hair_length})")
    else:
        feedback_parts.append(f"Hair params invalid (count={hair_count}, len={hair_length})")
    score += params_score
    
    # ================================================================
    # Criterion 4: Children configured (15 points)
    # ================================================================
    children_score = 0
    child_type = scene.get("child_type", "NONE")
    child_render = scene.get("child_render_count", 0)
    
    type_ok = child_type in ("SIMPLE", "INTERPOLATED")
    render_ok = child_render >= 50
    
    if type_ok and render_ok:
        children_score = 15
        feedback_parts.append(f"Children settings OK ({child_type}, {child_render})")
    elif type_ok:
        children_score = 8
        feedback_parts.append(f"Children type OK, but render count low ({child_render})")
    elif child_type != "NONE":
        children_score = 3
        feedback_parts.append(f"Children enabled but wrong type ({child_type})")
    else:
        feedback_parts.append("Children not enabled")
    score += children_score
    
    # ================================================================
    # Criterion 5: Fur material color (10 points)
    # ================================================================
    material_score = 0
    mat_found = scene.get("material_found", False)
    has_principled = scene.get("material_has_principled", False)
    base_color = scene.get("material_base_color", [0, 0, 0, 1])
    
    if mat_found and has_principled and len(base_color) >= 3:
        r, g, b = base_color[0], base_color[1], base_color[2]
        color_warm = (r > g > b) or (r > g and r > b)
        r_ok = r >= 0.4
        b_ok = b <= 0.2
        
        if color_warm and r_ok and b_ok:
            material_score = 10
            feedback_parts.append("Material color correct (warm brown)")
        elif r_ok:
            material_score = 5
            feedback_parts.append("Material reddish but not quite warm brown")
        else:
            material_score = 2
            feedback_parts.append(f"Material wrong color (R={r:.2f}, G={g:.2f}, B={b:.2f})")
    elif mat_found:
        material_score = 2
        feedback_parts.append("Material found but no Principled BSDF")
    else:
        feedback_parts.append("No material assigned")
    score += material_score
    
    # ================================================================
    # Criterion 6: Render output (15 points)
    # ================================================================
    render_score = 0
    render_exists = render_info.get("exists", False)
    render_size_kb = render_info.get("size_kb", 0)
    render_valid = render_info.get("valid_image", False)
    render_newer = render_info.get("newer_than_start", False)
    
    if render_exists and render_valid and render_size_kb > 50 and render_newer:
        render_score = 15
        feedback_parts.append(f"Render output valid ({render_size_kb:.1f}KB)")
    elif render_exists and render_valid:
        render_score = 5
        feedback_parts.append(f"Render exists but check failed (size/time)")
    else:
        feedback_parts.append("No valid render output")
    score += render_score
    
    # ================================================================
    # Criterion 7: Blend file saved (10 points)
    # ================================================================
    blend_score = 0
    blend_exists = blend_info.get("exists", False)
    blend_newer = blend_info.get("newer_than_start", False)
    blend_valid = scene.get("blend_file_valid", False)
    
    if blend_exists and blend_newer and blend_valid:
        blend_score = 10
        feedback_parts.append("Blend file saved")
    elif blend_exists:
        blend_score = 2
        feedback_parts.append("Blend file exists but check failed (time/validity)")
    else:
        feedback_parts.append("No blend file saved")
    score += blend_score
    
    # ================================================================
    # Final result
    # ================================================================
    passed = score >= 70
    
    return {
        "score": score,
        "max_score": max_score,
        "passed": passed,
        "feedback": "; ".join(feedback_parts),
        "details": details
    }