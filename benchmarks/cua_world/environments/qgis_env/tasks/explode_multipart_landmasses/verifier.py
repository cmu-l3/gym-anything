#!/usr/bin/env python3
"""
Verifier for Explode Multipart Geometries task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_explode_multipart_landmasses(traj, env_info, task_info):
    """
    Verify the multipart to singleparts conversion.
    
    Scoring Criteria:
    1. Output file exists (10 pts)
    2. Valid GeoJSON (10 pts)
    3. File created during task (10 pts)
    4. Feature count increased (indicating explosion) (25 pts)
    5. Geometry type is Polygon (not MultiPolygon) (25 pts)
    6. Attributes preserved (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # Retrieve result
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

    score = 0
    feedback_parts = []
    
    # 1. File Existence
    if result.get("file_exists"):
        score += 10
        feedback_parts.append("Output file found")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # 2. Validity
    if result.get("valid_geojson"):
        score += 10
        feedback_parts.append("Valid GeoJSON")
    else:
        feedback_parts.append("Invalid GeoJSON format")

    # 3. Creation Time
    if result.get("file_newly_created"):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp stale")

    # 4. Feature Count (The Core Logic)
    feat_count = result.get("feature_count", 0)
    if result.get("feature_count_increased") and feat_count > 0:
        score += 25
        feedback_parts.append(f"Feature count increased ({feat_count})")
    else:
        feedback_parts.append(f"Feature count did not increase ({feat_count})")

    # 5. Geometry Type
    geoms = result.get("geometry_types", {})
    if result.get("all_polygon"):
        score += 25
        feedback_parts.append("Geometries converted to Polygon")
    elif geoms.get("Polygon", 0) > 0:
        # Partial credit if mixed
        score += 10
        feedback_parts.append("Some geometries converted to Polygon")
    else:
        feedback_parts.append("Geometries remain MultiPolygon")

    # 6. Attributes
    if result.get("attributes_preserved"):
        score += 20
        feedback_parts.append("Attributes preserved")
    else:
        feedback_parts.append("Attributes missing")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }