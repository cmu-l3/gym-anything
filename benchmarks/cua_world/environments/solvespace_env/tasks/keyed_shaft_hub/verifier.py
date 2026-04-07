#!/usr/bin/env python3
"""
Verifier for keyed_shaft_hub task.
Parses the output STL mesh to check geometry details, validates file timestamps, and queries VLM on trajectories.
"""

import struct
import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_ascii_stl(filepath):
    triangles = []
    try:
        with open(filepath, 'r') as f:
            current_tri = []
            for line in f:
                parts = line.strip().split()
                if not parts:
                    continue
                if parts[0] == 'vertex':
                    current_tri.append((float(parts[1]), float(parts[2]), float(parts[3])))
                    if len(current_tri) == 3:
                        triangles.append(tuple(current_tri))
                        current_tri = []
    except Exception as e:
        logger.error(f"ASCII STL parse error: {e}")
    return triangles

def parse_stl(filepath):
    try:
        with open(filepath, 'rb') as f:
            header = f.read(80)
            if len(header) < 80:
                return []
            
            num_tri_bytes = f.read(4)
            if len(num_tri_bytes) < 4:
                return parse_ascii_stl(filepath)
            
            num_triangles = struct.unpack('<I', num_tri_bytes)[0]
            
            # Verify file size matches binary STL format expectations
            f.seek(0, 2)
            file_size = f.tell()
            expected_size = 84 + num_triangles * 50
            if file_size != expected_size:
                return parse_ascii_stl(filepath)
            
            f.seek(84)
            triangles = []
            for _ in range(num_triangles):
                data = f.read(50)
                if len(data) < 50:
                    break
                v1 = struct.unpack('<3f', data[12:24])
                v2 = struct.unpack('<3f', data[24:36])
                v3 = struct.unpack('<3f', data[36:48])
                triangles.append((v1, v2, v3))
            return triangles
    except Exception as e:
        logger.error(f"STL parse error: {e}")
        return []

def calc_stl_properties(triangles):
    if not triangles:
        return None
        
    min_x = min_y = min_z = float('inf')
    max_x = max_y = max_z = float('-inf')
    volume = 0.0
    
    for v1, v2, v3 in triangles:
        for v in (v1, v2, v3):
            min_x, max_x = min(min_x, v[0]), max(max_x, v[0])
            min_y, max_y = min(min_y, v[1]), max(max_y, v[1])
            min_z, max_z = min(min_z, v[2]), max(max_z, v[2])
            
        # Volume of tetrahedron from origin
        v32x = v2[1]*v3[2] - v2[2]*v3[1]
        v32y = v2[2]*v3[0] - v2[0]*v3[2]
        v32z = v2[0]*v3[1] - v2[1]*v3[0]
        vol = (v1[0]*v32x + v1[1]*v32y + v1[2]*v32z) / 6.0
        volume += vol
        
    return {
        "bbox": ((min_x, max_x), (min_y, max_y), (min_z, max_z)),
        "volume": abs(volume),
        "dimensions": (max_x - min_x, max_y - min_y, max_z - min_z)
    }

def verify_keyed_shaft_hub(traj, env_info, task_info):
    """
    Verify that the agent modeled the keyed shaft hub correctly.
    Checks file existence, timestamps, STL geometry (dimensions and volume), and uses VLM to confirm trajectory.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Parse JSON result
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

    score = 0
    feedback_parts = []
    
    slvs_exists = result.get('slvs_exists', False)
    slvs_created = result.get('slvs_created_during_task', False)
    stl_exists = result.get('stl_exists', False)
    stl_created = result.get('stl_created_during_task', False)
    
    if slvs_exists and slvs_created:
        score += 10
        feedback_parts.append("SLVS file created")
    elif slvs_exists:
        feedback_parts.append("SLVS file exists (but pre-dated task)")
        
    if stl_exists and stl_created:
        score += 10
        feedback_parts.append("STL file created")
    elif stl_exists:
        feedback_parts.append("STL file exists (but pre-dated task)")
        
    if not stl_exists:
        feedback_parts.append("Missing STL file - cannot verify geometry")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    # 2. Parse STL
    temp_stl = tempfile.NamedTemporaryFile(delete=False, suffix='.stl')
    props = None
    try:
        copy_from_env("/home/ga/Documents/SolveSpace/keyed_hub.stl", temp_stl.name)
        triangles = parse_stl(temp_stl.name)
        props = calc_stl_properties(triangles)
    except Exception as e:
        feedback_parts.append(f"STL parse error: {e}")
    finally:
        if os.path.exists(temp_stl.name):
            os.unlink(temp_stl.name)
            
    if not props:
        feedback_parts.append("Failed to parse valid STL geometry")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    dim_x, dim_y, dim_z = props["dimensions"]
    volume = props["volume"]
    
    # Identify the extrusion axis (the one closest to 25.0)
    dims = [dim_x, dim_y, dim_z]
    thickness_dim = min(dims, key=lambda d: abs(d - 25.0))
    other_dims = [d for d in dims]
    other_dims.remove(thickness_dim)
    
    # 3. Geometric Verification
    thickness_error = abs(thickness_dim - 25.0)
    if thickness_error < 0.5:
        score += 20
        feedback_parts.append(f"Thickness correct ({thickness_dim:.1f}mm)")
    else:
        feedback_parts.append(f"Thickness incorrect (got {thickness_dim:.1f}mm)")
        
    diam_error_1 = abs(other_dims[0] - 40.0)
    diam_error_2 = abs(other_dims[1] - 40.0)
    if diam_error_1 < 1.0 and diam_error_2 < 1.0:
        score += 20
        feedback_parts.append(f"Outer diameter correct (~{other_dims[0]:.1f}x{other_dims[1]:.1f}mm)")
    else:
        feedback_parts.append(f"Outer diameter incorrect (got {other_dims[0]:.1f}x{other_dims[1]:.1f}mm)")
        
    # Expected Volume bounds (approx 26710 mm3)
    if 26000 <= volume <= 27400:
        score += 20
        feedback_parts.append(f"Volume correct ({volume:.0f} mm3)")
    else:
        feedback_parts.append(f"Volume incorrect ({volume:.0f} mm3)")

    # 4. VLM Trajectory Verification
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                prompt = '''Look at these frames of a CAD session. 
Did the user successfully draw a 2D profile with a circular outer boundary and an inner hole featuring a rectangular keyway slot, and extrude it into a 3D solid?
Respond with JSON containing:
{
  "drew_keyway": true/false,
  "extruded_solid": true/false
}'''
                vlm_result = query_vlm(prompt=prompt, images=images)
                answer_str = str(vlm_result).lower()
                
                if '"drew_keyway": true' in answer_str or "'drew_keyway': true" in answer_str:
                    vlm_score += 10
                if '"extruded_solid": true' in answer_str or "'extruded_solid': true" in answer_str:
                    vlm_score += 10
                    
                feedback_parts.append(f"VLM trajectory verification: {vlm_score}/20")
        except Exception as e:
            feedback_parts.append(f"VLM verification skipped/failed: {e}")
            
    score += vlm_score

    # Check passing criteria
    key_criteria_met = stl_created and (thickness_error < 0.5) and (26000 <= volume <= 27400)
    passed = score >= 70 and key_criteria_met

    return {"passed": passed, "score": score, "feedback": " | ".join(feedback_parts)}