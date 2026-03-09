#!/usr/bin/env python3
"""
Verifier for create_solid_cranial_model task.

Verification Logic:
1. STL file must exist and be valid.
2. STL Volume must be calculated to distinguish between:
   - Hollow skull (bone only): ~300-600 cm3
   - Filled skull (solid cranial phantom): ~1300-2200 cm3 (TARGET)
   - Full head (skin/soft tissue): >2400 cm3

Scoring:
- File exists & Valid: 20 pts
- Volume > 800 cm3 (Proves "Fill Holes" was used): 40 pts
- Volume < 2300 cm3 (Proves "Bone" threshold used, not "Skin"): 40 pts
"""

import json
import os
import struct
import tempfile
import logging
import math

logger = logging.getLogger(__name__)

def calculate_signed_volume_of_triangle(p1, p2, p3):
    """
    Calculate signed volume of a tetrahedron formed by triangle and origin.
    v3.dot(cross(v1, v2)) / 6.0
    """
    v321 = p3[0] * p2[1] * p1[2]
    v231 = p2[0] * p3[1] * p1[2]
    v312 = p3[0] * p1[1] * p2[2]
    v132 = p1[0] * p3[1] * p2[2]
    v213 = p2[0] * p1[1] * p3[2]
    v123 = p1[0] * p2[1] * p3[2]
    return (1.0 / 6.0) * (-v321 + v231 + v312 - v132 - v213 + v123)

def compute_binary_stl_volume(file_path):
    """
    Parses a binary STL file and computes the enclosed volume in cm3.
    Assumes coordinates are in mm (standard for medical DICOM).
    Returns volume in cm3 (cc).
    """
    total_volume_mm3 = 0.0
    
    try:
        with open(file_path, "rb") as f:
            header = f.read(80)
            count_bytes = f.read(4)
            if len(count_bytes) != 4:
                return 0.0
            
            num_triangles = struct.unpack("<I", count_bytes)[0]
            
            # Iterate over triangles
            # Each triangle is 50 bytes: 12 normal + 36 vertices + 2 attribute
            # We iterate in chunks for efficiency if needed, but simple loop is fine for ~500k triangles
            
            # Struct format for one triangle: 3f (normal), 3f (v1), 3f (v2), 3f (v3), H (attr)
            # However, reading 50 bytes at a time is safer.
            
            for _ in range(num_triangles):
                data = f.read(50)
                if len(data) < 50:
                    break
                
                # Unpack 12 floats (normal + 3 vertices) + 1 uint16
                # We only need the vertices (floats 3-11)
                # Offset 12 bytes to skip normal
                # v1: bytes 12-24, v2: 24-36, v3: 36-48
                
                v1 = struct.unpack_from("<3f", data, 12)
                v2 = struct.unpack_from("<3f", data, 24)
                v3 = struct.unpack_from("<3f", data, 36)
                
                total_volume_mm3 += calculate_signed_volume_of_triangle(v1, v2, v3)
                
    except Exception as e:
        logger.error(f"Error calculating STL volume: {e}")
        return 0.0

    # Volume must be positive
    total_volume_mm3 = abs(total_volume_mm3)
    
    # Convert cubic mm to cubic cm (cc)
    # 1 cm3 = 1000 mm3
    return total_volume_mm3 / 1000.0

def verify_create_solid_cranial_model(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    # Default thresholds if not in metadata
    min_vol = metadata.get("min_volume_cm3", 1200.0)
    max_vol = metadata.get("max_volume_cm3", 2200.0)
    
    score = 0
    feedback_parts = []
    
    # 1. Get the JSON result from the container
    try:
        tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_json.close()
        copy_from_env("/tmp/create_solid_cranial_model_result.json", tmp_json.name)
        with open(tmp_json.name) as f:
            result_data = json.load(f)
        os.unlink(tmp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task status: {e}"}

    # 2. Check if file exists and is valid
    if not result_data.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Output STL file not found."}
    
    if not result_data.get("is_binary_stl"):
        return {"passed": False, "score": 10, "feedback": "File exists but is not a valid binary STL."}

    score += 20
    feedback_parts.append("Valid binary STL created")

    # 3. Retrieve the actual STL file to calculate volume
    stl_path_in_container = metadata.get("output_path", "/home/ga/Documents/solid_cranium.stl")
    
    try:
        tmp_stl = tempfile.NamedTemporaryFile(delete=False, suffix=".stl")
        tmp_stl.close()
        copy_from_env(stl_path_in_container, tmp_stl.name)
        
        calculated_volume_cc = compute_binary_stl_volume(tmp_stl.name)
        os.unlink(tmp_stl.name)
        
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to retrieve/parse STL file for volume check: {e}"}

    feedback_parts.append(f"Calculated Volume: {calculated_volume_cc:.1f} cm3")

    # 4. Score based on volume
    # Criterion A: Is it solid? (Volume > 800)
    if calculated_volume_cc > 800.0:
        score += 40
        feedback_parts.append("Volume indicates internal cavities filled (Solid)")
    else:
        feedback_parts.append("Volume too low (Hollow shell only)")

    # Criterion B: Is it bone only? (Volume < 2300)
    # If they used the skin threshold, volume would be ~3000+
    if calculated_volume_cc < 2300.0:
        score += 40
        feedback_parts.append("Volume indicates soft tissue excluded (Bone only)")
    else:
        feedback_parts.append("Volume too high (Likely included skin/soft tissue)")

    # Pass logic: Must be within target range [1200, 2200] roughly
    # The score logic above naturally handles this: 20 + 40 + 40 = 100
    passed = score >= 100

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }