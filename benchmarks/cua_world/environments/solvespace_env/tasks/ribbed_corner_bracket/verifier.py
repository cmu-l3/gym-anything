#!/usr/bin/env python3
"""
Verifier for ribbed_corner_bracket task.

Multi-Criteria Verification:
1. File Existence & Timestamps (10 points) - Prevents "do nothing" gaming.
2. STL Mesh Export (15 points) - Validates the 2D sketch is a valid closed loop capable of extrusion.
3. Bounding Box Dimensions (35 points) - Checks X/Y geometry and Z-axis Two-Sided symmetry.
4. Total Volume Check (20 points) - Highly robust check combining both extrusions (L-bracket + gusset).
5. VLM Trajectory (20 points) - Proves the agent physically interacted with the CAD software.
"""

import os
import json
import struct
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_binary_stl(filepath):
    """
    Dependency-free binary STL parser to calculate volume and bounding box.
    Returns dict with volume and bounding box limits, or None if invalid.
    """
    try:
        with open(filepath, 'rb') as f:
            header = f.read(80)
            if len(header) < 80: return None
            
            count_bytes = f.read(4)
            if len(count_bytes) < 4: return None
            
            num_triangles = struct.unpack('<I', count_bytes)[0]
            if num_triangles == 0: return None

            volume = 0.0
            min_x = min_y = min_z = float('inf')
            max_x = max_y = max_z = float('-inf')

            for _ in range(num_triangles):
                data = f.read(50)
                if len(data) < 50: break
                
                # Unpack triangle vertices (skipping normal and attr bytes)
                v1 = struct.unpack('<3f', data[12:24])
                v2 = struct.unpack('<3f', data[24:36])
                v3 = struct.unpack('<3f', data[36:48])

                # Calculate signed volume of tetrahedron from origin
                cross_x = v2[1]*v3[2] - v2[2]*v3[1]
                cross_y = v2[2]*v3[0] - v2[0]*v3[2]
                cross_z = v2[0]*v3[1] - v2[1]*v3[0]
                tetra_vol = (v1[0]*cross_x + v1[1]*cross_y + v1[2]*cross_z) / 6.0
                volume += tetra_vol

                # Update bounding box
                for v in (v1, v2, v3):
                    min_x = min(min_x, v[0])
                    max_x = max(max_x, v[0])
                    min_y = min(min_y, v[1])
                    max_y = max(max_y, v[1])
                    min_z = min(min_z, v[2])
                    max_z = max(max_z, v[2])

        return {
            "volume": abs(volume),
            "bbox": {
                "min_x": min_x, "max_x": max_x,
                "min_y": min_y, "max_y": max_y,
                "min_z": min_z, "max_z": max_z
            }
        }
    except Exception as e:
        logger.error(f"Error parsing STL: {e}")
        return None


def verify_ribbed_bracket(traj, env_info, task_info):
    """Verifies the ribbed corner bracket creation and metrics."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_vol = metadata.get('expected_volume', 57250)
    vol_tol = metadata.get('volume_tolerance', 2000)
    exp_bbox = metadata.get('bbox', {})
    bbox_tol = metadata.get('bbox_tolerance', 1.0)

    score = 0
    feedback_parts = []

    # 1. Read Task Result JSON
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

    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    stl_generated = result.get('stl_generated', False)

    if output_exists and file_created:
        score += 10
        feedback_parts.append("File created successfully")
    elif output_exists:
        feedback_parts.append("File exists but was not created during task")
    else:
        feedback_parts.append("Bracket model not saved")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. STL Geometry Check
    stl_valid = False
    if stl_generated:
        temp_stl = tempfile.NamedTemporaryFile(delete=False, suffix='.stl')
        try:
            copy_from_env("/tmp/ribbed_bracket.stl", temp_stl.name)
            geometry = parse_binary_stl(temp_stl.name)
            
            if geometry:
                stl_valid = True
                score += 15
                feedback_parts.append("Valid 3D mesh exported")
                
                vol = geometry["volume"]
                bbox = geometry["bbox"]
                
                # Check Bounding Box X (~60mm wide)
                x_range = bbox['max_x'] - bbox['min_x']
                if abs(x_range - 60.0) <= bbox_tol:
                    score += 10
                    feedback_parts.append(f"X-Dim correct ({x_range:.1f}mm)")
                else:
                    feedback_parts.append(f"X-Dim incorrect ({x_range:.1f}mm)")

                # Check Bounding Box Y (~80mm high)
                y_range = bbox['max_y'] - bbox['min_y']
                if abs(y_range - 80.0) <= bbox_tol:
                    score += 10
                    feedback_parts.append(f"Y-Dim correct ({y_range:.1f}mm)")
                else:
                    feedback_parts.append(f"Y-Dim incorrect ({y_range:.1f}mm)")

                # Check Bounding Box Z (Symmetry -20 to 20)
                z_range = bbox['max_z'] - bbox['min_z']
                is_centered_z = abs(bbox['min_z'] - exp_bbox['min_z']) <= bbox_tol and \
                                abs(bbox['max_z'] - exp_bbox['max_z']) <= bbox_tol
                
                if abs(z_range - 40.0) <= bbox_tol and is_centered_z:
                    score += 15
                    feedback_parts.append(f"Z-Symmetry correct ({bbox['min_z']:.1f} to {bbox['max_z']:.1f})")
                elif abs(z_range - 40.0) <= bbox_tol:
                    score += 5
                    feedback_parts.append(f"Z-Depth correct but NOT symmetric ({bbox['min_z']:.1f} to {bbox['max_z']:.1f})")
                else:
                    feedback_parts.append(f"Z-Depth incorrect ({z_range:.1f}mm)")

                # Check Total Volume
                if abs(vol - expected_vol) <= vol_tol:
                    score += 20
                    feedback_parts.append(f"Volume correct ({vol:.0f} mm3)")
                else:
                    feedback_parts.append(f"Volume incorrect ({vol:.0f} mm3, expected ~{expected_vol})")
            else:
                feedback_parts.append("STL generated but could not be parsed")
                
        except Exception as e:
            logger.error(f"Failed processing STL: {e}")
            feedback_parts.append("STL processing error")
        finally:
            if os.path.exists(temp_stl.name):
                os.unlink(temp_stl.name)
    else:
        feedback_parts.append("Failed to generate 3D model (sketch likely open/invalid)")

    # 3. VLM Trajectory Verification
    vlm_feedback = "VLM not queried"
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm and stl_valid:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            
            prompt = (
                "Review these trajectory frames from a user working in SolveSpace. "
                "Did the user draw a 2D sketch and use extrusion tools? "
                "Reply with 'YES' if CAD interaction is visible, otherwise 'NO'."
            )
            vlm_response = query_vlm(images=frames, prompt=prompt)
            
            if vlm_response.get("success") and "YES" in vlm_response.get("answer", "").upper():
                score += 20
                vlm_feedback = "Trajectory validated"
            else:
                vlm_feedback = "Trajectory lacked clear CAD interaction"
        except Exception as e:
            logger.error(f"VLM error: {e}")
            vlm_feedback = "VLM validation failed"
            
        feedback_parts.append(vlm_feedback)
    elif not stl_valid:
        feedback_parts.append("Skipped VLM due to invalid 3D geometry")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }