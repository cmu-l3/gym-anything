#!/usr/bin/env python3
"""
Verifier for reuleaux_rotor_parametric task.
"""

import os
import json
import struct
import tempfile
import logging
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_stl_volume_and_bbox(stl_path):
    """
    Parses an STL file (binary or ascii) and calculates its volume and bounding box.
    """
    volume = 0.0
    min_pt = np.array([np.inf, np.inf, np.inf])
    max_pt = np.array([-np.inf, -np.inf, -np.inf])

    try:
        with open(stl_path, 'rb') as f:
            header = f.read(80)
            if len(header) < 80:
                return None, None
            
            # Check if ASCII
            if header.startswith(b'solid '):
                f.seek(0)
                lines = f.readlines()
                vertices = []
                for line in lines:
                    line = line.strip()
                    if line.startswith(b'vertex'):
                        parts = line.split()
                        if len(parts) >= 4:
                            v = [float(parts[1]), float(parts[2]), float(parts[3])]
                            vertices.append(v)
                            min_pt = np.minimum(min_pt, v)
                            max_pt = np.maximum(max_pt, v)
                            
                            if len(vertices) == 3:
                                v1, v2, v3 = np.array(vertices[0]), np.array(vertices[1]), np.array(vertices[2])
                                volume += np.dot(v1, np.cross(v2, v3)) / 6.0
                                vertices = []
            else:
                # Binary STL
                num_triangles_data = f.read(4)
                if len(num_triangles_data) == 4:
                    num_triangles = struct.unpack('<I', num_triangles_data)[0]
                    for _ in range(num_triangles):
                        data = f.read(50)
                        if len(data) == 50:
                            # normals (12), v1 (12), v2 (12), v3 (12), attr (2)
                            unpacked = struct.unpack('<12fH', data)
                            v1 = np.array(unpacked[3:6])
                            v2 = np.array(unpacked[6:9])
                            v3 = np.array(unpacked[9:12])
                            
                            min_pt = np.minimum(min_pt, np.minimum(v1, np.minimum(v2, v3)))
                            max_pt = np.maximum(max_pt, np.maximum(v1, np.maximum(v2, v3)))
                            
                            volume += np.dot(v1, np.cross(v2, v3)) / 6.0
                            
        return abs(volume), (max_pt - min_pt)
    except Exception as e:
        logger.error(f"Failed to parse STL: {e}")
        return None, None


def check_slvs_construction_workflow(slvs_path):
    """
    Checks if the SolveSpace recipe uses construction geometry and appropriate constraints.
    """
    construction_lines = 0
    arcs = 0
    extrude_found = False
    
    try:
        with open(slvs_path, 'r', encoding='utf-8') as f:
            content = f.read()
            # Entity.type=11000 is line segment
            # Entity.construction=1 means construction geometry
            lines = content.split('\n')
            
            in_entity = False
            is_line = False
            is_construction = False
            is_arc = False
            
            for line in lines:
                if line.startswith('Entity.h.v='):
                    if in_entity and is_line and is_construction:
                        construction_lines += 1
                    if in_entity and is_arc:
                        arcs += 1
                    in_entity = True
                    is_line = False
                    is_construction = False
                    is_arc = False
                elif line.startswith('Entity.type=11000'):
                    is_line = True
                elif line.startswith('Entity.type=12000'): # Arc
                    is_arc = True
                elif line.startswith('Entity.construction=1'):
                    is_construction = True
                elif line.startswith('Group.type=5100'): # Extrude group
                    extrude_found = True
                    
            # catch the last entity
            if in_entity and is_line and is_construction:
                construction_lines += 1
            if in_entity and is_arc:
                arcs += 1
                
        return construction_lines >= 3, arcs >= 3, extrude_found
    except Exception as e:
        logger.error(f"Failed to parse SLVS: {e}")
        return False, False, False


def verify_reuleaux_rotor(traj, env_info, task_info):
    """
    Verify the Reuleaux rotor parametric task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_vol = metadata.get('expected_volume_mm3', 28325.5)
    vol_tol = metadata.get('volume_tolerance_percent', 5.0) / 100.0
    dim_tol = metadata.get('dimension_tolerance_mm', 1.5)
    
    score = 0
    feedback_parts = []
    
    # 1. Read JSON result
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
            
    slvs_exists = result.get('slvs', {}).get('exists', False)
    stl_exists = result.get('stl', {}).get('exists', False)
    slvs_created = result.get('slvs', {}).get('created_during_task', False)
    stl_created = result.get('stl', {}).get('created_during_task', False)

    if not (slvs_exists and stl_exists):
        return {"passed": False, "score": 0, "feedback": "Required output files (.slvs or .stl) missing."}
        
    if not (slvs_created or stl_created):
        return {"passed": False, "score": 0, "feedback": "Files exist but were not created during this task session (anti-gaming)."}
        
    score += 15
    feedback_parts.append("Files successfully created")

    # 2. Analyze SLVS File
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    try:
        copy_from_env(metadata.get('expected_slvs_path'), temp_slvs.name)
        has_scaffold, has_arcs, has_extrude = check_slvs_construction_workflow(temp_slvs.name)
        
        if has_scaffold:
            score += 15
            feedback_parts.append("Construction scaffold found")
        else:
            feedback_parts.append("Missing construction scaffold")
            
        if has_arcs:
            score += 10
            feedback_parts.append("Circular arcs found")
            
    except Exception as e:
        feedback_parts.append(f"SLVS parsing error: {e}")
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)

    # 3. Analyze STL File
    temp_stl = tempfile.NamedTemporaryFile(delete=False, suffix='.stl')
    try:
        copy_from_env(metadata.get('expected_stl_path'), temp_stl.name)
        vol, bbox = parse_stl_volume_and_bbox(temp_stl.name)
        
        if vol is not None and bbox is not None:
            # Sort bounding box to find the thickness (smallest dimension) and widths (largest)
            dims = sorted(list(bbox))
            z_dim = dims[0]  # Thickness is the smallest dimension (12)
            y_dim = dims[1]  # Width
            x_dim = dims[2]  # Width
            
            # Check dimensions (Width ~ 60, Thickness ~ 12)
            if abs(z_dim - 12.0) <= dim_tol:
                score += 15
                feedback_parts.append(f"Thickness correct ({z_dim:.1f}mm)")
            else:
                feedback_parts.append(f"Thickness incorrect ({z_dim:.1f}mm)")
                
            if abs(x_dim - 60.0) <= dim_tol and abs(y_dim - 60.0) <= dim_tol:
                score += 15
                feedback_parts.append(f"Bounding dimensions correct ({x_dim:.1f}x{y_dim:.1f})")
            else:
                feedback_parts.append(f"Bounding dimensions incorrect ({x_dim:.1f}x{y_dim:.1f})")
                
            # Check volume
            vol_diff = abs(vol - expected_vol)
            max_vol_diff = expected_vol * vol_tol
            
            if vol_diff <= max_vol_diff:
                score += 15
                feedback_parts.append(f"Volume accurate ({vol:.1f} mm3)")
            else:
                feedback_parts.append(f"Volume inaccurate ({vol:.1f} mm3 vs expected {expected_vol})")
                
    except Exception as e:
        feedback_parts.append(f"STL parsing error: {e}")
    finally:
        if os.path.exists(temp_stl.name):
            os.unlink(temp_stl.name)
            
    # 4. VLM Verification of workflow (to prevent STL drop-in)
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        if frames and final_img:
            prompt = """
            You are evaluating a CAD agent drawing a 3D Reuleaux triangle in SolveSpace.
            Review the sequence of frames (first 4 are trajectory, last is final).
            Did the agent use the SolveSpace interface to draw lines, convert them to construction geometry, and sketch arcs around them to build the shape?
            Respond strictly with JSON:
            {"used_interface_to_draw": true/false}
            """
            try:
                vlm_resp = query_vlm(prompt=prompt, images=frames + [final_img])
                if vlm_resp.get("parsed", {}).get("used_interface_to_draw", False):
                    score += 15
                    feedback_parts.append("VLM verified manual drawing workflow")
                else:
                    feedback_parts.append("VLM did not observe active CAD drawing")
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")

    # Determine final success
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }