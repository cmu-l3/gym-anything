#!/usr/bin/env python3
"""
Verifier for parametric_stair_stringer task.

Verification Criteria:
1. Files exist and were created during task (Anti-gaming) (10 pts)
2. SLVS contains >= 11 line segments (15 pts)
3. STL valid with proper thickness/solid geometry (15 pts)
4. STL dimensions precisely match expected [40, 720, 1120] bounds (20 pts)
5. Parametric intent: SLVS uses equal lengths, therefore <= 6 distance constraints (20 pts)
6. VLM Trajectory Check: Agent actually worked in CAD to make stair geometry (20 pts)
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_stair_stringer(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_dims = sorted(metadata.get('expected_dims', [40.0, 720.0, 1120.0]))
    max_distance_constraints = metadata.get('max_distance_constraints', 6)
    min_lines = metadata.get('min_lines', 11)

    score = 0
    feedback_parts = []
    
    # 1. Read JSON stats
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

    task_start = result.get('task_start', 0)
    slvs_exists = result.get('slvs_exists', False)
    slvs_mtime = result.get('slvs_mtime', 0)
    stl_info = result.get('stl_info', {})

    # Check File Existence & Anti-Gaming
    if slvs_exists and stl_info.get('exists', False):
        if slvs_mtime > task_start:
            score += 10
            feedback_parts.append("✅ Files saved successfully during task.")
        else:
            feedback_parts.append("❌ Files exist but were created BEFORE task started (Gaming detected).")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    else:
        feedback_parts.append("❌ Required files (.slvs, .stl) not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Parse SLVS file contents for constraints and segments
    slvs_text = ""
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    try:
        copy_from_env("/home/ga/Documents/SolveSpace/stair_stringer.slvs", temp_slvs.name)
        with open(temp_slvs.name, 'r', encoding='utf-8', errors='ignore') as f:
            slvs_text = f.read()
    except Exception as e:
        logger.warning(f"Could not read SLVS file: {e}")
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)
    
    # Analyze SLVS Text
    # Request.type=200 is a line segment
    num_lines = slvs_text.count("Request.type=200")
    # Constraint.type=10 is a distance constraint
    num_distance_const = slvs_text.count("Constraint.type=10")
    
    if num_lines >= min_lines:
        score += 15
        feedback_parts.append(f"✅ Profile complexity met ({num_lines} lines).")
    else:
        feedback_parts.append(f"❌ Insufficient lines in sketch ({num_lines} found, expected >={min_lines}).")

    if 0 < num_distance_const <= max_distance_constraints:
        score += 20
        feedback_parts.append(f"✅ Parametric intent verified ({num_distance_const} distance constraints used).")
    elif num_distance_const > max_distance_constraints:
        feedback_parts.append(f"❌ Sketch over-dimensioned without equal relations ({num_distance_const} distance constraints found, max {max_distance_constraints}).")
    else:
        feedback_parts.append("❌ No dimension constraints found (Not parametric).")

    # 3 & 4. Analyze STL Properties
    if "error" not in stl_info and stl_info.get("num_tris", 0) > 20:
        score += 15
        feedback_parts.append("✅ Valid 3D solid STL exported.")
        
        # We sort the actual dimensions to make it orientation-independent
        dx = stl_info.get("dx", 0)
        dy = stl_info.get("dy", 0)
        dz = stl_info.get("dz", 0)
        actual_dims = sorted([dx, dy, dz])
        
        # Check if actual dims match expected within 2%
        dims_match = True
        for a, e in zip(actual_dims, expected_dims):
            if abs(a - e) / e > 0.02:
                dims_match = False
                break
                
        if dims_match:
            score += 20
            feedback_parts.append(f"✅ Bounding box perfectly matches constraints {actual_dims}.")
        else:
            feedback_parts.append(f"❌ Bounding box mismatch. Expected roughly {expected_dims}, got {actual_dims}.")
    else:
        feedback_parts.append("❌ STL file is invalid, empty, or not extruded.")

    # 5. VLM Verification (Trajectory checking)
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots from a CAD session in SolveSpace.
        1. Did the user create a zig-zag stair-like sketch profile?
        2. Did the user extrude it into a 3D solid body?
        Answer with a strict JSON format:
        {"made_stair_sketch": true/false, "made_3d_extrusion": true/false}
        """
        
        vlm_res = query_vlm(images=frames + [final_frame], prompt=prompt)
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("made_stair_sketch"): score += 10
            if parsed.get("made_3d_extrusion"): score += 10
            if parsed.get("made_stair_sketch") and parsed.get("made_3d_extrusion"):
                feedback_parts.append("✅ VLM confirmed visual workflow.")
            else:
                feedback_parts.append("⚠️ VLM did not confirm complete visual workflow.")
        else:
            # Fallback points if VLM fails but programmatic logic strongly passes
            if score >= 60:
                score += 20 
                feedback_parts.append("⚠️ VLM failed but programmatic checks passed.")
    else:
        if score >= 60: score += 20 # Grant points if VLM unavailable but task perfect

    passed = score >= 80  # Requires files, dimensions, and good constraints

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }