#!/usr/bin/env python3
"""
Verifier for evaluate_morphological_closing_impact task.

Checks:
1. Both raw and closed STL files exist.
2. Both are valid binary STLs with significant geometry (>10k triangles).
3. Volume(closed) > Volume(raw). The "Closing" operation (Dilation -> Erosion) 
   fills internal voids, increasing total volume. If volume decreases (Opening) 
   or stays identical (No Op), the task fails.
"""

import json
import os
import tempfile
import struct
import numpy as np
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def calculate_stl_volume(file_path):
    """
    Calculate volume of a binary STL file using signed tetrahedron method.
    Returns volume in mm^3.
    """
    try:
        with open(file_path, "rb") as f:
            header = f.read(80)
            count_bytes = f.read(4)
            if len(count_bytes) != 4:
                return 0.0
            
            num_triangles = struct.unpack("<I", count_bytes)[0]
            if num_triangles == 0:
                return 0.0

            # Each triangle is 50 bytes: 12 floats (normal + 3 vertices) + 2 byte attr
            # Reading chunk by chunk to avoid memory issues with huge files
            volume = 0.0
            
            # Use numpy for faster processing if possible
            dtype = np.dtype([
                ('normal', np.float32, (3,)),
                ('v1', np.float32, (3,)),
                ('v2', np.float32, (3,)),
                ('v3', np.float32, (3,)),
                ('attr', np.uint16, (1,))
            ])
            
            # Read all data at once (standard skull STLs are ~50MB, manageable)
            data = np.fromfile(f, dtype=dtype, count=num_triangles)
            
            v1 = data['v1']
            v2 = data['v2']
            v3 = data['v3']
            
            # Signed volume of tetrahedron from origin to triangle
            # Vol = (1/6) * dot(cross(v1, v2), v3)
            # Using scalar triple product rule: det([v1, v2, v3])
            
            # Cross product v1 x v2
            cross_x = v1[:, 1] * v2[:, 2] - v1[:, 2] * v2[:, 1]
            cross_y = v1[:, 2] * v2[:, 0] - v1[:, 0] * v2[:, 2]
            cross_z = v1[:, 0] * v2[:, 1] - v1[:, 1] * v2[:, 0]
            
            # Dot with v3
            dot = cross_x * v3[:, 0] + cross_y * v3[:, 1] + cross_z * v3[:, 2]
            
            total_volume = np.sum(dot) / 6.0
            return abs(total_volume) # STL volumes are usually positive, but winding order matters
            
    except Exception as e:
        logger.error(f"Error calculating volume for {file_path}: {e}")
        return 0.0

def verify_evaluate_morphological_closing_impact(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    
    # Files to verify
    raw_stl_remote = "/home/ga/Documents/raw_skull.stl"
    closed_stl_remote = "/home/ga/Documents/closed_skull.stl"
    
    # Temp files for local analysis
    tmp_dir = tempfile.mkdtemp()
    raw_local = os.path.join(tmp_dir, "raw.stl")
    closed_local = os.path.join(tmp_dir, "closed.stl")
    json_local = os.path.join(tmp_dir, "result.json")
    
    try:
        # 1. Check metadata JSON from export_result.sh
        try:
            copy_from_env("/tmp/task_result.json", json_local)
            with open(json_local) as f:
                result_meta = json.load(f)
        except:
            result_meta = {}

        # 2. Check existence & basic validity (40 points)
        files_exist = result_meta.get("raw_exists", False) and result_meta.get("closed_exists", False)
        
        if files_exist:
            score += 20
            feedback_parts.append("Both STL files exist")
        else:
            feedback_parts.append("Missing one or both STL files")
            # If files don't exist, we can't do volume checks
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
            
        triangles_ok = (result_meta.get("raw_triangles", 0) > 10000 and 
                        result_meta.get("closed_triangles", 0) > 10000)
        
        if triangles_ok:
            score += 20
            feedback_parts.append("Geometry valid (>10k triangles)")
        else:
            feedback_parts.append("Geometry too simple or invalid")
            
        # 3. Volume Logic Analysis (60 points)
        # Copy actual files to host for heavy math
        try:
            copy_from_env(raw_stl_remote, raw_local)
            copy_from_env(closed_stl_remote, closed_local)
            
            vol_raw = calculate_stl_volume(raw_local)
            vol_closed = calculate_stl_volume(closed_local)
            
            feedback_parts.append(f"Raw Vol: {vol_raw/1000:.1f}cc")
            feedback_parts.append(f"Closed Vol: {vol_closed/1000:.1f}cc")
            
            if vol_raw < 1000: # Sanity check (skull should be hundreds of cc)
                 feedback_parts.append("Calculated volume too small (corrupt mesh?)")
                 logic_score = 0
            elif vol_closed > vol_raw * 1.0001: # At least slightly larger (allowing float noise)
                # Success: Closing adds volume
                logic_score = 60
                feedback_parts.append("Volume INCREASE confirmed (Closing applied)")
            elif vol_closed < vol_raw * 0.9999:
                # Failure: Volume decreased (Likely "Opening" or "Erosion")
                logic_score = 0
                feedback_parts.append("Volume DECREASED (Wrong operation? Expected Closing)")
            else:
                # Failure: Volume identical
                logic_score = 0
                feedback_parts.append("Volume IDENTICAL (Operation not applied/exported)")
                
            score += logic_score
            
        except Exception as e:
            feedback_parts.append(f"Volume calculation failed: {str(e)}")
            
    finally:
        # Cleanup
        import shutil
        shutil.rmtree(tmp_dir, ignore_errors=True)
        
    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }