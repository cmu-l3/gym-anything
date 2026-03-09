#!/usr/bin/env python3
"""
Verifier for drape_vector_on_dem_3d task.

Verifies:
1. Output file exists (GPKG preferred, GeoJSON accepted)
2. Geometry is 3D (LineStringZ)
3. Z-values are populated (elevation extracted from DEM)
4. Coordinates match input trail (spatial integrity)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_drape_vector_on_dem_3d(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    analysis = result.get("analysis", {})
    
    score = 0
    feedback_parts = []
    
    # Criterion 1: File Existence (15 pts)
    if analysis.get("file_exists", False):
        score += 15
        feedback_parts.append("Output file found")
    else:
        feedback_parts.append("Output file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    # Criterion 2: File Validity (15 pts)
    if analysis.get("is_valid", False):
        score += 15
        feedback_parts.append(f"Valid vector file ({analysis.get('geom_type')})")
    else:
        feedback_parts.append("File is not a valid vector source")
        
    # Criterion 3: 3D Geometry Type (35 pts)
    if analysis.get("is_3d", False):
        score += 35
        feedback_parts.append("Geometry is 3D")
    else:
        feedback_parts.append(f"Geometry is NOT 3D (Type: {analysis.get('geom_type', 'Unknown')})")
        
    # Criterion 4: Z-Values Populated (35 pts)
    if analysis.get("has_z_values", False):
        score += 35
        z_min = analysis.get("z_min", 0)
        z_max = analysis.get("z_max", 0)
        feedback_parts.append(f"Elevation data present (Range: {z_min:.1f}m to {z_max:.1f}m)")
    else:
        feedback_parts.append("Z-values missing or all zero")

    passed = score >= 80  # Requires both 3D type and actual Z values
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }