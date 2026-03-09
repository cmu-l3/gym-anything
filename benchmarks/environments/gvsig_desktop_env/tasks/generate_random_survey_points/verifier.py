#!/usr/bin/env python3
"""
Verifier for generate_random_survey_points task.

Verifies:
1. Shapefile creation and validity.
2. Feature count (must be exactly 40).
3. Spatial constraints (must be within Madagascar).
4. Attribute schema (LON/LAT fields added).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_random_survey_points(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_count = metadata.get('target_count', 40)
    
    # Approximate bounds for Madagascar (padded slightly)
    # Correct bounds are approx 43E to 51E, 11S to 26S
    target_bbox = metadata.get('target_bbox', {
        "min_x": 43.0, "max_x": 51.0, 
        "min_y": -26.0, "max_y": -11.0
    })

    # Retrieve result file
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

    analysis = result.get('shapefile_analysis', {})
    score = 0
    feedback_parts = []
    
    # 1. File Existence and Timestamp (20 pts)
    if analysis.get('exists') and analysis.get('valid_timestamps'):
        score += 20
        feedback_parts.append("Shapefile created successfully")
    elif analysis.get('exists'):
        score += 10
        feedback_parts.append("Shapefile exists but timestamp is invalid (pre-existing?)")
    else:
        return {"passed": False, "score": 0, "feedback": "Output shapefile not found"}

    # 2. Feature Count (20 pts)
    actual_count = analysis.get('count', 0)
    if actual_count == expected_count:
        score += 20
        feedback_parts.append(f"Correct feature count ({actual_count})")
    else:
        feedback_parts.append(f"Incorrect feature count: expected {expected_count}, got {actual_count}")
        # Partial credit if close
        if abs(actual_count - expected_count) <= 5:
            score += 10

    # 3. Spatial Validity (30 pts)
    # Check if the shapefile's bounding box is contained within (or very close to) Madagascar
    # Note: If points are randomly generated *inside* Madagascar, the bbox of points 
    # must be strictly inside the country bbox.
    bbox = analysis.get('bbox', [0, 0, 0, 0]) # minx, miny, maxx, maxy
    min_x, min_y, max_x, max_y = bbox
    
    # Check if bounds are roughly reasonable (not 0,0,0,0 and not global)
    is_spatial_valid = (
        min_x >= target_bbox['min_x'] - 1.0 and
        max_x <= target_bbox['max_x'] + 1.0 and
        min_y >= target_bbox['min_y'] - 1.0 and
        max_y <= target_bbox['max_y'] + 1.0
    )
    
    # Check that it's not empty or zero
    has_extent = (max_x - min_x) > 0.1 and (max_y - min_y) > 0.1
    
    if is_spatial_valid and has_extent:
        score += 30
        feedback_parts.append("Points are spatially located within Madagascar")
    else:
        feedback_parts.append(f"Spatial check failed: BBox {bbox} outside target {target_bbox}")

    # 4. Attribute Fields (15 pts)
    fields = [f.upper() for f in analysis.get('fields', [])]
    has_lon = 'LON' in fields or 'LONGITUDE' in fields
    has_lat = 'LAT' in fields or 'LATITUDE' in fields
    
    if has_lon and has_lat:
        score += 15
        feedback_parts.append("Coordinate fields (LON/LAT) added")
    elif has_lon or has_lat:
        score += 5
        feedback_parts.append("Missing one coordinate field")
    else:
        feedback_parts.append("Coordinate fields missing")

    # 5. App Running (15 pts) (Implicitly checked by file creation, but good for completeness)
    if result.get('app_was_running', False):
        score += 15
    
    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }