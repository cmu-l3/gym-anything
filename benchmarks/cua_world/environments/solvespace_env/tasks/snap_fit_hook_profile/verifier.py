#!/usr/bin/env python3
"""
Verifier for snap_fit_hook_profile task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_snap_fit_hook_profile(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0

    # Read the JSON result
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

    # 1. SLVS File (10 points)
    slvs_exists = result.get('slvs_exists', False)
    slvs_created = result.get('slvs_created', False)
    if slvs_exists and slvs_created:
        score += 10
        feedback_parts.append("SLVS file created")
    else:
        feedback_parts.append("SLVS file missing or not created during task")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Read the SLVS file
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    slvs_text = ""
    try:
        copy_from_env("/tmp/snap_fit_hook.slvs", temp_slvs.name)
        with open(temp_slvs.name, 'r') as f:
            slvs_text = f.read()
    except Exception as e:
        feedback_parts.append(f"Could not read SLVS file: {e}")
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)

    # 2. Polygon complexity (at least 6 lines) (15 points)
    line_count = slvs_text.count("Entity.type=11000")
    if line_count >= 6:
        score += 15
        feedback_parts.append(f"Polygon has {line_count} line segments (>=6)")
    else:
        feedback_parts.append(f"Polygon only has {line_count} lines (expected 6)")

    # 3. Horizontal and Vertical Constraints (15 points)
    h_count = slvs_text.count("Constraint.type=10")
    v_count = slvs_text.count("Constraint.type=20")
    if h_count >= 2 and v_count >= 3:
        score += 15
        feedback_parts.append(f"H/V constraints present (H:{h_count}, V:{v_count})")
    elif h_count > 0 or v_count > 0:
        score += 5
        feedback_parts.append(f"Some H/V constraints missing (H:{h_count}, V:{v_count})")
    else:
        feedback_parts.append("No H/V constraints found")

    # 4. Dimensional constraints (22, 18, 2, 1.5) (30 points)
    # Looking out for negatively signed parameters depending on drawing direction
    has_22 = "val=22." in slvs_text or "val=-22." in slvs_text
    has_18 = "val=18." in slvs_text or "val=-18." in slvs_text
    has_2 = "val=2." in slvs_text or "val=-2." in slvs_text
    has_1_5 = "val=1.5" in slvs_text or "val=-1.5" in slvs_text
    
    dims_found = sum([has_22, has_18, has_2, has_1_5])
    if dims_found == 4:
        score += 30
        feedback_parts.append("All requested dimensions found (22, 18, 2, 1.5)")
    else:
        score += dims_found * 7
        feedback_parts.append(f"Found {dims_found}/4 requested dimensions")

    # 5. Extrusion and Extrusion depth (8.0) (20 points)
    has_extrude = "Group.type=5002" in slvs_text or "Group.type=5100" in slvs_text
    has_8 = "val=8." in slvs_text or "val=-8." in slvs_text

    if has_extrude and has_8:
        score += 20
        feedback_parts.append("Extrude group with 8.0mm depth found")
    elif has_extrude:
        score += 10
        feedback_parts.append("Extrude group found but depth not 8.0mm")
    else:
        feedback_parts.append("No extrude group found")

    # 6. STL Export (10 points)
    stl_exists = result.get('stl_exists', False)
    stl_created = result.get('stl_created', False)
    stl_size = result.get('stl_size_bytes', 0)
    
    if stl_exists and stl_created and stl_size > 100:
        score += 10
        feedback_parts.append(f"STL exported correctly ({stl_size} bytes)")
    elif stl_exists:
        score += 5
        feedback_parts.append("STL exists but was not created correctly")
    else:
        feedback_parts.append("STL not exported")

    # VLM Verification component
    vlm_feedback = "VLM check not performed"
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        if final:
            prompt = (
                "Look at these screenshots of a SolveSpace CAD modeling session. "
                "Did the user create a cantilever snap-fit hook cross-section (a shape with a straight beam, a catch hook at the end, and a sloped tip) "
                "and apply dimensions to it?"
            )
            try:
                vlm_res = query_vlm(images=frames + [final], prompt=prompt)
                if vlm_res.get("success"):
                    vlm_feedback = f"VLM Analysis: {vlm_res.get('parsed', vlm_res.get('text', 'No text returned'))}"
                else:
                    vlm_feedback = f"VLM Error: {vlm_res.get('error')}"
            except Exception as e:
                vlm_feedback = f"VLM Error: {e}"

    feedback_parts.append(vlm_feedback)

    # Key criteria for pass: SLVS created, has sufficient dimensions, and is extruded
    key_criteria_met = slvs_created and dims_found >= 3 and has_extrude
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }