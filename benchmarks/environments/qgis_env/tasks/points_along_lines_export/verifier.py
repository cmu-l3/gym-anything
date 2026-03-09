#!/usr/bin/env python3
"""
Verifier for Points Along Lines task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_points_along_lines_export(traj, env_info, task_info):
    """
    Verify the Points Along Lines task.
    
    Checks:
    1. Output file exists (15 pts)
    2. Valid GeoJSON format (15 pts)
    3. All Point geometry (15 pts)
    4. Reasonable feature count 8-30 (15 pts)
    5. Points within bounding box (15 pts)
    6. Spatial distribution (15 pts)
    7. File is newly created (10 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
    
    score = 0
    max_score = 100
    details = {}
    feedback_parts = []
    
    # Criterion 1: Output file exists (15 pts)
    file_exists = task_result.get('file_exists', False)
    details['file_exists'] = file_exists
    if file_exists:
        score += 15
        feedback_parts.append("Output file exists")
    else:
        feedback_parts.append("Output file not found")
        # Critical failure
        return {
            "score": 0,
            "passed": False,
            "feedback": "Output file not found",
            "details": details
        }
    
    # Criterion 2: Valid GeoJSON format (15 pts)
    valid_geojson = task_result.get('valid_geojson', False)
    details['valid_geojson'] = valid_geojson
    if valid_geojson:
        score += 15
        feedback_parts.append("Valid GeoJSON")
    else:
        feedback_parts.append("Invalid GeoJSON structure")
        # Critical failure for subsequent checks
        return {
            "score": score,
            "passed": False,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # Criterion 3: All Point geometry (15 pts)
    all_point = task_result.get('all_point_geometry', False)
    details['all_point_geometry'] = all_point
    details['geometry_types'] = task_result.get('geometry_types', [])
    if all_point:
        score += 15
        feedback_parts.append("Geometry is Point type")
    else:
        feedback_parts.append(f"Incorrect geometry types: {details['geometry_types']}")
    
    # Criterion 4: Reasonable feature count (15 pts)
    feature_count = task_result.get('feature_count', 0)
    details['feature_count'] = feature_count
    # With 0.05 degree interval on ~0.75 total degrees of line, expect 10-20 points
    # Allow wider range 8-30 for different tool behaviors (endpoints etc)
    reasonable_count = 8 <= feature_count <= 30
    details['reasonable_count'] = reasonable_count
    if reasonable_count:
        score += 15
        feedback_parts.append(f"Count correct ({feature_count})")
    elif feature_count > 2:
        # Partial credit if they generated some points but not the right amount
        score += 7
        feedback_parts.append(f"Count incorrect but plausible ({feature_count})")
    else:
        feedback_parts.append(f"Count too low ({feature_count})")
    
    # Criterion 5: Points within bounding box (15 pts)
    in_bbox = task_result.get('coordinates_in_bbox', False)
    if in_bbox:
        score += 15
        feedback_parts.append("Points inside expected area")
    else:
        feedback_parts.append("Points outside expected area")
    
    # Criterion 6: Spatial distribution (15 pts)
    spatial_dist = task_result.get('spatial_distribution', False)
    if spatial_dist:
        score += 15
        feedback_parts.append("Points are distributed")
    else:
        feedback_parts.append("Points are clustered (not distributed)")
    
    # Criterion 7: File is newly created (10 pts)
    is_new = task_result.get('is_new_file', False)
    if is_new:
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp not verified")
    
    # Final check
    passed = score >= 60 and valid_geojson
    
    return {
        "score": score,
        "passed": passed,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }