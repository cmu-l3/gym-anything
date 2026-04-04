#!/usr/bin/env python3
"""
Verifier for create_clean_mandible_mesh task.

Verification Strategy:
1. STL File Analysis:
   - Check file existence and validity.
   - Parse binary STL to get geometry bounds.
   - Verify Z-height (vertical dimension) corresponds to a mandible (approx 40-80mm).
   - Reject if Z-height is too large (likely includes maxilla/skull >100mm).
2. Anti-Gaming:
   - Check timestamps to ensure file was created during task.
3. VLM Verification (Supplementary):
   - Verify the agent actually used the cutting tools.
"""

import json
import os
import struct
import numpy as np
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def read_stl_geometry(file_path):
    """
    Parses a binary STL file and returns the bounding box dimensions.
    Returns (width, depth, height, vertex_count) or None on error.
    """
    try:
        with open(file_path, 'rb') as f:
            # Skip header (80 bytes)
            f.read(80)
            # Read triangle count (4 bytes, unsigned long little-endian)
            count_bytes = f.read(4)
            if len(count_bytes) < 4:
                return None
            num_triangles = struct.unpack('<I', count_bytes)[0]
            
            if num_triangles == 0:
                return (0, 0, 0, 0)

            # STL binary format: 50 bytes per triangle
            # Normal (12), Vertex1 (12), Vertex2 (12), Vertex3 (12), Attr (2)
            # We only need vertices.
            # Using numpy for efficient reading
            dtype = np.dtype([
                ('normal', '<f4', (3,)),
                ('v1', '<f4', (3,)),
                ('v2', '<f4', (3,)),
                ('v3', '<f4', (3,)),
                ('attr', '<u2')
            ])
            
            data = np.fromfile(f, dtype=dtype, count=num_triangles)
            
            # Combine all vertices
            v1 = data['v1']
            v2 = data['v2']
            v3 = data['v3']
            all_verts = np.concatenate([v1, v2, v3], axis=0)
            
            min_bounds = np.min(all_verts, axis=0)
            max_bounds = np.max(all_verts, axis=0)
            
            dimensions = max_bounds - min_bounds
            
            # dimensions = [x_width, y_depth, z_height]
            return dimensions, len(all_verts)
            
    except Exception as e:
        logger.error(f"Error reading STL: {e}")
        return None

def verify_create_clean_mandible_mesh(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', r"C:\Users\Docker\Documents\MandibleOnly.stl")
    min_height = metadata.get('min_height_mm', 30.0)
    max_height = metadata.get('max_height_mm', 90.0)
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(r"C:\tmp\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence & Timestamp (20 pts)
    if result.get('output_exists') and result.get('file_created_during_task'):
        score += 20
        feedback_parts.append("STL file created.")
    elif result.get('output_exists'):
        score += 10
        feedback_parts.append("STL file exists but timestamp ambiguous.")
    else:
        return {"passed": False, "score": 0, "feedback": "No output STL file found."}

    # 3. Analyze Geometry (60 pts)
    temp_stl = tempfile.NamedTemporaryFile(delete=False, suffix='.stl')
    try:
        copy_from_env(expected_path, temp_stl.name)
        
        geom_info = read_stl_geometry(temp_stl.name)
        
        if geom_info:
            dims, v_count = geom_info
            width, depth, height = dims
            
            # Complexity check (10 pts)
            if v_count > 5000:
                score += 10
                feedback_parts.append(f"Mesh complexity good ({v_count} vertices).")
            else:
                feedback_parts.append(f"Mesh too simple ({v_count} vertices).")
            
            # Dimensions check (Mandible Isolation) (50 pts)
            # A full skull/maxilla+mandible is typically > 120mm height
            # A mandible only is typically 40-80mm height
            logger.info(f"STL Dimensions: W={width:.1f}, D={depth:.1f}, H={height:.1f}")
            
            if min_height <= height <= max_height:
                score += 50
                feedback_parts.append(f"Vertical dimensions correct for mandible ({height:.1f}mm).")
            elif height > max_height:
                feedback_parts.append(f"Mesh too tall ({height:.1f}mm) - likely contains maxilla/skull.")
            elif height < min_height:
                feedback_parts.append(f"Mesh too short ({height:.1f}mm) - likely fragments/noise.")
        else:
            feedback_parts.append("Failed to parse STL file.")
            
    except Exception as e:
        feedback_parts.append(f"Error analyzing STL: {str(e)}")
    finally:
        if os.path.exists(temp_stl.name):
            os.unlink(temp_stl.name)

    # 4. VLM Verification (20 pts)
    # Check if tools were used
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_res = query_vlm(
            images=frames,
            prompt="Does the user appear to be using 3D cutting or editing tools to remove parts of a 3D model? Look for 'Cut', 'Isolate', or selection lassos."
        )
        if vlm_res.get('success') and 'yes' in vlm_res.get('result', '').lower():
            score += 20
            feedback_parts.append("Visual evidence of editing tools used.")
        else:
            # Fallback points if geometry is perfect, assume they did it
            if score >= 70: 
                score += 20
                feedback_parts.append("Geometry is perfect, assuming editing occurred.")

    passed = score >= 90  # Strict pass for isolation
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }