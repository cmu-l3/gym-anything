#!/usr/bin/env python3
"""
Verifier for Count Points in Polygons task.
"""

import json
import os
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_count_points_in_polygons(traj, env_info, task_info):
    """
    Verify that the user correctly counted points within polygons and exported the result.
    
    Scoring Criteria:
    1. File exists (15 pts)
    2. Valid GeoJSON (15 pts)
    3. Contains Polygon/MultiPolygon features (correct geometry) (15 pts)
    4. Has a count field (NUMPOINTS or similar) (20 pts)
    5. Count values are reasonable (total > 180, indicating points were actually counted) (15 pts)
    6. File newly created (anti-gaming) (10 pts)
    7. File size check (> 50KB) (10 pts)
    
    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result from container
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
    
    # 1. File exists (15 pts)
    if result.get("file_exists", False):
        score += 15
        feedback_parts.append("Output file found")
    else:
        feedback_parts.append("Output file NOT found")
        # Early exit if file doesn't exist
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    # 2. Valid GeoJSON (15 pts)
    if result.get("is_valid_geojson", False):
        score += 15
        feedback_parts.append("Valid GeoJSON")
    else:
        feedback_parts.append("Invalid or corrupted GeoJSON")

    # 3. Polygon features present (15 pts)
    poly_count = result.get("polygon_count", 0)
    # Natural Earth countries dataset has ~177 features
    if poly_count >= 150:
        score += 15
        feedback_parts.append(f"Correct geometry type ({poly_count} polygons)")
    elif poly_count > 0:
        score += 5
        feedback_parts.append(f"Contains polygons but fewer than expected ({poly_count})")
    else:
        feedback_parts.append("No polygon geometries found (wrong layer exported?)")

    # 4. Count field present (20 pts)
    if result.get("has_count_field", False):
        score += 20
        fname = result.get("count_field_name", "unknown")
        feedback_parts.append(f"Count field '{fname}' found")
    else:
        feedback_parts.append("No count field (NUMPOINTS) found")

    # 5. Reasonable count values (15 pts)
    summary = result.get("count_values_summary", {})
    total_count = summary.get("total", 0)
    positive_features = summary.get("positive_count_features", 0)
    
    # Total count for world cities usually around 243 in this dataset
    if total_count >= 180:
        score += 15
        feedback_parts.append(f"Point counts reasonable (Total: {total_count})")
    elif total_count > 0:
        score += 5
        feedback_parts.append(f"Counts too low (Total: {total_count}, expected >180)")
    else:
        feedback_parts.append("All counts are zero")

    # 6. Newly created file (10 pts)
    if result.get("file_created_after_task_start", False):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp indicates pre-existing file")

    # 7. File size check (10 pts)
    # The countries file with attributes is roughly 200KB-1MB depending on precision
    size_bytes = result.get("file_size_bytes", 0)
    if size_bytes > 50000:  # 50KB
        score += 10
        feedback_parts.append("File size normal")
    else:
        feedback_parts.append(f"File suspiciously small ({size_bytes} bytes)")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }