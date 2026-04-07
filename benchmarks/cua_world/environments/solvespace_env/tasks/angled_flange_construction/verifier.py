#!/usr/bin/env python3
"""
Verifier for angled_flange_construction task.

Verifies:
1. Agent created the requested .slvs file during the episode.
2. The SLVS file contains an Extrude group.
3. The SLVS file contains a Construction Entity (toggled line).
4. The constraints match the requested values (80, 10, 35, 45, 5).
5. VLM verification of the trajectory frames confirms a 3D solid flange
   with a properly placed hole on an angled axis.
"""

import os
import json
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_angled_flange(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Tolerances and expected values
    expected_od = metadata.get('target_outer_diameter', 80.0)
    expected_id = metadata.get('target_hole_diameter', 10.0)
    expected_len = metadata.get('target_radius_length', 35.0)
    expected_ang = metadata.get('target_angle', 45.0)
    expected_depth = metadata.get('target_extrusion_depth', 5.0)

    score = 0
    feedback_parts = []
    
    # 1. Read JSON Results
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    result = {}
    
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # Anti-gaming: Ensure file was created during task
    output_exists = result.get('output_exists', False)
    created_during = result.get('file_created_during_task', False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output .slvs file not found. Task failed."}
    
    if not created_during:
        feedback_parts.append("Warning: File existed before task (possible anti-gaming violation).")
    else:
        score += 15
        feedback_parts.append("File correctly created during task.")

    # 2. Parse SLVS Content
    has_extrude = False
    has_construction = False
    params = []
    
    try:
        copy_from_env("/tmp/angled_flange.slvs", temp_slvs.name)
        with open(temp_slvs.name, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip()
                if "Group.type=5100" in line:
                    has_extrude = True
                if "Entity.construction=1" in line:
                    has_construction = True
                if line.startswith("Param.val="):
                    try:
                        val = float(line.split("=")[1])
                        params.append(val)
                    except ValueError:
                        pass
    except Exception as e:
        logger.error(f"Error parsing .slvs: {e}")
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)
            
    # Function to check if a value exists within parameter array (handling tolerance)
    def has_val(target, tol=0.1):
        return any(abs(p - target) <= tol for p in params)

    if has_extrude:
        score += 15
        feedback_parts.append("Extrusion group found.")
    else:
        feedback_parts.append("Missing Extrusion (Group 5100).")

    if has_construction:
        score += 15
        feedback_parts.append("Construction entity found.")
    else:
        feedback_parts.append("No construction geometry used (Entity.construction=1 missing).")

    # Check Dimensions (Accepting both radius and diameter cases just in case)
    dim_score = 0
    if has_val(expected_od) or has_val(expected_od / 2): dim_score += 6
    if has_val(expected_id) or has_val(expected_id / 2): dim_score += 6
    if has_val(expected_len): dim_score += 6
    # Angles might be stored as 45, 135, 225, 315 depending on quadrant
    if has_val(expected_ang) or has_val(180 - expected_ang) or has_val(180 + expected_ang) or has_val(360 - expected_ang): dim_score += 6
    if has_val(expected_depth): dim_score += 6
    
    score += dim_score
    feedback_parts.append(f"Parametric dimension constraints match score: {dim_score}/30.")

    # 3. VLM Trajectory Verification
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        if final_img:
            frames.append(final_img)
            
        prompt = """You are evaluating a parametric CAD task in SolveSpace.
        The agent was instructed to:
        1. Draw a circular flange base.
        2. Draw a construction line (typically dashed or green) at a 45-degree angle.
        3. Draw a smaller hole centered at the end of that construction line.
        4. Extrude the sketch into a 3D solid plate.
        
        Look at the trajectory frames and final screenshot.
        Return a JSON object:
        {
            "used_construction_line": true/false,
            "hole_is_off_center": true/false,
            "is_3d_extruded": true/false
        }
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and vlm_res.get("success") and "parsed" in vlm_res:
                parsed = vlm_res["parsed"]
                if parsed.get("used_construction_line"): vlm_score += 10
                if parsed.get("hole_is_off_center"): vlm_score += 5
                if parsed.get("is_3d_extruded"): vlm_score += 10
                feedback_parts.append(f"VLM Visual confirmation score: {vlm_score}/25.")
            else:
                feedback_parts.append("VLM visual verification could not be parsed.")
        except Exception as e:
            logger.error(f"VLM query failed: {e}")
            feedback_parts.append("VLM visual verification failed.")
            
    score += vlm_score

    # Passing Threshold: At least 70 points AND must have used construction geometry
    passed = score >= 70 and has_construction and output_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }