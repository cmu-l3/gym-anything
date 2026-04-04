#!/usr/bin/env python3
import json
import os
import struct
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_split_part(traj, env_info, task_info):
    """
    Verifies that the T8 bracket was split correctly into two STL files.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # --- Constants & Expectations ---
    # The T8 bracket is roughly 60mm tall. Split at 15mm.
    # We expect the bottom part to be roughly Z=[0, 15]
    # We expect the top part to be roughly Z=[15, 60]
    EXPECTED_SPLIT_Z = 15.0
    TOLERANCE_MM = task_info.get('metadata', {}).get('tolerance_mm', 1.0)
    
    # We will score based on:
    # 1. Files exist and created during task (30 pts)
    # 2. Files are valid STLs (10 pts)
    # 3. Bottom geometry (bounding box Z-max near 15mm) (30 pts)
    # 4. Top geometry (bounding box Z-min near 15mm) (30 pts)

    score = 0
    feedback_lines = []
    
    # --- Load Result JSON ---
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    # --- Verify File Existence & Timing ---
    bottom_info = result.get("bottom_file", {})
    top_info = result.get("top_file", {})
    
    files_exist = bottom_info.get("exists") and top_info.get("exists")
    files_fresh = bottom_info.get("created_during_task") and top_info.get("created_during_task")
    
    if files_exist:
        score += 15
        feedback_lines.append("Both output files exist.")
    else:
        feedback_lines.append(f"Missing files: Bottom={bottom_info.get('exists')}, Top={top_info.get('exists')}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_lines)}

    if files_fresh:
        score += 15
        feedback_lines.append("Files were created during the task window.")
    else:
        feedback_lines.append("Files were NOT created during the task (stale data?).")
        # Critical failure if data is old
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_lines)}

    # --- Geometry Analysis ---
    def analyze_stl_remote(remote_path):
        """Copies STL from env and returns (is_valid, bounds, volume)"""
        local_tf = tempfile.NamedTemporaryFile(delete=False, suffix='.stl')
        try:
            copy_from_env(remote_path, local_tf.name)
            return parse_stl(local_tf.name)
        except Exception as e:
            logger.error(f"Error processing {remote_path}: {e}")
            return False, None, 0.0
        finally:
            if os.path.exists(local_tf.name):
                os.unlink(local_tf.name)

    # Analyze Bottom
    b_valid, b_bounds, b_vol = analyze_stl_remote(bottom_info["path"])
    # Analyze Top
    t_valid, t_bounds, t_vol = analyze_stl_remote(top_info["path"])

    if b_valid and t_valid:
        score += 10
        feedback_lines.append("Both files are valid STL meshes.")
    else:
        feedback_lines.append("One or more files are not valid STLs.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_lines)}

    # --- Check Split Height (Bottom Part) ---
    # Bottom part should span Z_min ~ 0 to Z_max ~ 15
    if b_bounds:
        z_min, z_max = b_bounds[2], b_bounds[5]
        # Check Z-max is close to split height
        if abs(z_max - EXPECTED_SPLIT_Z) < TOLERANCE_MM:
            score += 30
            feedback_lines.append(f"Bottom part height correct (Z_max={z_max:.2f}mm).")
        else:
            feedback_lines.append(f"Bottom part height incorrect (Z_max={z_max:.2f}mm, expected {EXPECTED_SPLIT_Z}mm).")
    
    # --- Check Split Height (Top Part) ---
    # Top part should span Z_min ~ 15 to Z_max > 15
    if t_bounds:
        z_min, z_max = t_bounds[2], t_bounds[5]
        # Check Z-min is close to split height
        if abs(z_min - EXPECTED_SPLIT_Z) < TOLERANCE_MM:
            score += 30
            feedback_lines.append(f"Top part base correct (Z_min={z_min:.2f}mm).")
        else:
            feedback_lines.append(f"Top part base incorrect (Z_min={z_min:.2f}mm, expected {EXPECTED_SPLIT_Z}mm).")

    return {
        "passed": score >= 90,
        "score": score,
        "feedback": " | ".join(feedback_lines)
    }

def parse_stl(filename):
    """
    Parses a binary STL file to calculate bounding box and volume.
    Returns (valid, (minx, miny, minz, maxx, maxy, maxz), volume)
    """
    try:
        with open(filename, "rb") as f:
            header = f.read(80)
            if len(header) < 80:
                return False, None, 0.0
            
            # Read number of triangles
            count_bytes = f.read(4)
            if len(count_bytes) < 4:
                return False, None, 0.0
            
            num_triangles = struct.unpack("<I", count_bytes)[0]
            
            # Sanity check file size: 80 + 4 + 50*num_triangles
            expected_size = 84 + 50 * num_triangles
            file_size = os.path.getsize(filename)
            if file_size != expected_size:
                # Might be ASCII STL, but FreeCAD default is Binary. 
                # For this task we assume standard FreeCAD output.
                # If size mismatches significantly, fail.
                # However, sometimes slight byte diffs occur. 
                pass

            min_point = [float('inf')] * 3
            max_point = [float('-inf')] * 3
            total_volume = 0.0

            # Iterate triangles
            # Record format: Normal (3f), V1 (3f), V2 (3f), V3 (3f), Attr (2s) = 50 bytes
            for _ in range(num_triangles):
                data = f.read(50)
                if len(data) < 50:
                    break
                
                # Unpack 12 floats (normal + 3 vertices) + uint16
                # We only need vertices for bounds/volume
                floats = struct.unpack("<12f", data[:48])
                
                v1 = (floats[3], floats[4], floats[5])
                v2 = (floats[6], floats[7], floats[8])
                v3 = (floats[9], floats[10], floats[11])
                
                # Update Bounds
                for v in [v1, v2, v3]:
                    for i in range(3):
                        if v[i] < min_point[i]: min_point[i] = v[i]
                        if v[i] > max_point[i]: max_point[i] = v[i]

                # Signed Volume of tetrahedron from origin
                # vol = (v1 . (v2 x v3)) / 6
                cross_x = v2[1]*v3[2] - v2[2]*v3[1]
                cross_y = v2[2]*v3[0] - v2[0]*v3[2]
                cross_z = v2[0]*v3[1] - v2[1]*v3[0]
                
                dot = v1[0]*cross_x + v1[1]*cross_y + v1[2]*cross_z
                total_volume += dot

            return True, tuple(min_point + max_point), abs(total_volume) / 6.0
            
    except Exception as e:
        logger.warning(f"Failed to parse STL {filename}: {e}")
        return False, None, 0.0