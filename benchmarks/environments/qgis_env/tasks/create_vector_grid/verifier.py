#!/usr/bin/env python3
"""
Verifier for create_vector_grid task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_vector_grid(traj, env_info, task_info):
    """
    Verify that a vector grid was created correctly.
    
    Criteria:
    1. Output file exists (15 pts)
    2. Valid GeoJSON file (15 pts)
    3. Contains Polygon geometries (15 pts)
    4. Feature count is reasonable (10-40) (15 pts)
    5. Grid covers the correct extent (20 pts)
    6. Cell size is approximately 0.1 degrees (20 pts)
    
    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
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
            
    logger.info(f"Task result: {result}")
    
    score = 0
    feedback_parts = []
    
    # 1. Check file existence
    if result.get("file_exists"):
        score += 15
        feedback_parts.append("Output file found")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found"}
        
    # 2. Check validity
    if result.get("valid_geojson"):
        score += 15
        feedback_parts.append("Valid GeoJSON")
    else:
        feedback_parts.append("Invalid GeoJSON format")
        
    # 3. Check geometry type
    if result.get("is_polygon"):
        score += 15
        feedback_parts.append("Correct geometry type (Polygon)")
    else:
        feedback_parts.append("Incorrect geometry type (expected Polygon)")
        
    # 4. Check feature count
    count = result.get("feature_count", 0)
    # Expected is 6x3 = 18. Allow buffer.
    if 10 <= count <= 40:
        score += 15
        feedback_parts.append(f"Feature count correct ({count})")
    else:
        feedback_parts.append(f"Feature count out of range ({count}, expected ~18)")
        
    # 5. Check extent
    if result.get("bounds_correct"):
        score += 20
        feedback_parts.append("Grid covers study area")
    else:
        bbox = result.get("bbox")
        feedback_parts.append(f"Grid extent mismatch or missing")
        
    # 6. Check cell size
    if result.get("cell_size_correct"):
        score += 20
        feedback_parts.append("Cell size approx 0.1 deg")
    else:
        w = result.get("avg_cell_width", 0)
        h = result.get("avg_cell_height", 0)
        feedback_parts.append(f"Incorrect cell size ({w:.3f}x{h:.3f})")
        
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }