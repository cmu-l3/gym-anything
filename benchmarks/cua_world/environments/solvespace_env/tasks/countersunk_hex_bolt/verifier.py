#!/usr/bin/env python3
"""
Verifier for countersunk_hex_bolt task.

Performs robust verification combining:
1. Output file metadata checks (existence, size, timestamps)
2. STL file geometrical parsing (Calculates precise Volume and Bounding Box dimensions)
3. SLVS file structural parsing (Detects Revolve groups, Extrude groups, and Boolean differences)
4. VLM visual validation of trajectories to ensure proper workflow
"""

import os
import json
import struct
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt specifically asks about the trajectory and UI usage
VLM_PROMPT = """You are evaluating a user's CAD session in SolveSpace based on these trajectory screenshots.
Review the images to answer these questions:
1. Did the user successfully use the Lathe (Revolve) tool to create a round, cylindrical, or conical 3D object?
2. Did the user sketch a hexagon on one of the flat faces of the object?
3. Did the user extrude that hexagon into the solid to create a hole or cut (Boolean difference)?
4. Is the SolveSpace user interface actively being used (Property Browser, menus, toolbars)?

Focus on the progression of the model.
Respond ONLY with a JSON object:
{
    "revolved_solid_created": true/false,
    "hexagon_cut_attempted": true/false,
    "ui_used": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}
"""

def parse_stl_geometry(filepath):
    """
    Parses a binary or ASCII STL file to calculate its physical volume 
    and bounding box dimensions. Requires no external libraries.
    """
    volume = 0.0
    min_coords = [float('inf')] * 3
    max_coords = [float('-inf')] * 3

    try:
        with open(filepath, 'rb') as f:
            header = f.read(80)
            header_str = header[:5].decode('ascii', errors='ignore').lower()

            if header_str == 'solid':
                # Parse ASCII STL
                f.seek(0)
                content = f.read().decode('ascii', errors='ignore')
                import re
                vertices = re.findall(
                    r'vertex\s+([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\s+([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\s+([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)', 
                    content
                )
                for i in range(0, len(vertices), 3):
                    if i + 2 >= len(vertices): break
                    v1 = [float(x) for x in vertices[i]]
                    v2 = [float(x) for x in vertices[i+1]]
                    v3 = [float(x) for x in vertices[i+2]]
                    
                    for v in (v1, v2, v3):
                        for j in range(3):
                            min_coords[j] = min(min_coords[j], v[j])
                            max_coords[j] = max(max_coords[j], v[j])
                    
                    # Signed volume of tetrahedron
                    volume += (v1[0]*v2[1]*v3[2] - v1[0]*v2[2]*v3[1] - v1[1]*v2[0]*v3[2] + v1[1]*v2[2]*v3[0] + v1[2]*v2[0]*v3[1] - v1[2]*v2[1]*v3[0]) / 6.0
            else:
                # Parse Binary STL
                num_tris_data = f.read(4)
                if len(num_tris_data) < 4:
                    return 0.0, [0,0,0], [0,0,0]
                num_tris = struct.unpack('<I', num_tris_data)[0]
                for _ in range(num_tris):
                    data = f.read(50)
                    if len(data) < 50: break
                    unpacked = struct.unpack('<12fH', data)
                    v1 = unpacked[3:6]
                    v2 = unpacked[6:9]
                    v3 = unpacked[9:12]
                    
                    for v in (v1, v2, v3):
                        for j in range(3):
                            min_coords[j] = min(min_coords[j], v[j])
                            max_coords[j] = max(max_coords[j], v[j])
                            
                    volume += (v1[0]*v2[1]*v3[2] - v1[0]*v2[2]*v3[1] - v1[1]*v2[0]*v3[2] + v1[1]*v2[2]*v3[0] + v1[2]*v2[0]*v3[1] - v1[2]*v2[1]*v3[0]) / 6.0

        dimensions = [max_coords[i] - min_coords[i] for i in range(3)]
        return abs(volume), dimensions
    except Exception as e:
        logger.error(f"Failed to parse STL: {e}")
        return 0.0, [0, 0, 0]


def verify_countersunk_bolt(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verifier error: copy_from_env not available."}

    metadata = task_info.get('metadata', {})
    expected_slvs = metadata.get('expected_slvs')
    expected_stl = metadata.get('expected_stl')
    
    score = 0
    feedback = []

    # 1. READ EXPORT JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            results = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    slvs_data = results.get('slvs', {})
    stl_data = results.get('stl', {})

    # File Existence and Anti-Gaming Checks
    if not slvs_data.get('exists') or not stl_data.get('exists'):
        return {"passed": False, "score": 0, "feedback": "Failed: Required output files (.slvs or .stl) do not exist."}
    
    if not slvs_data.get('created_during_task') or not stl_data.get('created_during_task'):
        return {"passed": False, "score": 0, "feedback": "Failed: Output files were not created/modified during the task session."}

    score += 15
    feedback.append("Files successfully created.")

    # 2. EVALUATE STL GEOMETRY
    temp_stl = tempfile.NamedTemporaryFile(delete=False, suffix='.stl')
    try:
        copy_from_env(expected_stl, temp_stl.name)
        volume, dimensions = parse_stl_geometry(temp_stl.name)
        dimensions.sort() # Sort to easily check length vs width without worrying about orientation
        
        # Check Bounding Box Dimensions
        if dimensions[2] >= 34.0 and dimensions[1] >= 14.0 and dimensions[1] <= 18.0:
            score += 25
            feedback.append(f"STL bounding box matches expected profile dimensions ({dimensions[0]:.1f}x{dimensions[1]:.1f}x{dimensions[2]:.1f} mm).")
        else:
            feedback.append(f"STL bounding box incorrect: {dimensions[0]:.1f}x{dimensions[1]:.1f}x{dimensions[2]:.1f} mm.")

        # Check Geometric Volume
        if metadata.get('volume_min') <= volume <= metadata.get('volume_max'):
            score += 20
            feedback.append(f"STL Volume correct ({volume:.1f} mm³).")
        else:
            feedback.append(f"STL Volume incorrect: {volume:.1f} mm³ (Expected ~2300 mm³).")

    except Exception as e:
        logger.error(f"Error evaluating STL: {e}")
    finally:
        if os.path.exists(temp_stl.name):
            os.unlink(temp_stl.name)

    # 3. EVALUATE SLVS STRUCTURE
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    try:
        copy_from_env(expected_slvs, temp_slvs.name)
        with open(temp_slvs.name, 'r', encoding='utf-8', errors='ignore') as f:
            slvs_content = f.read()
            
            # Check for Revolve operation
            if "Group.type=5200" in slvs_content:
                score += 10
                feedback.append("Revolve operation detected.")
            else:
                feedback.append("Revolve operation missing.")

            # Check for Extrude operation
            if "Group.type=5100" in slvs_content:
                score += 10
                feedback.append("Secondary extrude operation detected.")
            else:
                feedback.append("Secondary extrude operation missing.")
                
            # Check for Boolean Difference (cut)
            # Group.combine=1 signifies Difference in SolveSpace
            if "Group.combine=1" in slvs_content or "Group.op=1" in slvs_content:
                score += 5
                feedback.append("Boolean difference applied.")

    except Exception as e:
        logger.error(f"Error evaluating SLVS: {e}")
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)

    # 4. VLM VERIFICATION (Trajectory check)
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            try:
                vlm_resp = query_vlm(images=frames, prompt=VLM_PROMPT)
                if vlm_resp.get('success'):
                    parsed = vlm_resp.get('parsed', {})
                    if parsed.get('revolved_solid_created') and parsed.get('hexagon_cut_attempted'):
                        score += 15
                        feedback.append("VLM confirms Revolve and Extrude Cut workflow visually.")
                    else:
                        feedback.append(f"VLM issue: {parsed.get('reasoning', 'Could not confirm visual progression.')}")
            except Exception as e:
                logger.error(f"VLM analysis failed: {e}")
                
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "evaluated_volume": volume if 'volume' in locals() else 0,
            "evaluated_dimensions": dimensions if 'dimensions' in locals() else [0,0,0]
        }
    }