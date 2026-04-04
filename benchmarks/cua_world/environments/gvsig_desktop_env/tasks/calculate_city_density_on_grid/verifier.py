#!/usr/bin/env python3
"""
Verifier for calculate_city_density_on_grid task.

Verifies:
1. Output shapefile exists and was created during the task.
2. Output is a Polygon grid (geometry type 5).
3. Grid dimensions are correct (approx 162 features for 20x20 deg global grid).
4. Spatial join was performed (attribute field contains counts summing to ~243).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_city_density_grid(traj, env_info, task_info):
    """
    Verify the city density grid task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    expected_min_features = metadata.get('expected_feature_count_min', 150)
    expected_max_features = metadata.get('expected_feature_count_max', 180)
    expected_total_cities = metadata.get('expected_total_cities', 243)
    cities_tolerance = metadata.get('cities_tolerance', 15)

    # Copy result file
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

    analysis = result.get('analysis', {})
    score = 0
    feedback_parts = []
    
    # 1. File Existence (20 pts)
    if analysis.get('exists'):
        score += 20
        feedback_parts.append("Output file created")
    else:
        return {"passed": False, "score": 0, "feedback": "Output shapefile not found"}

    # 2. Created During Task (Anti-gaming) (10 pts)
    if analysis.get('created_during_task'):
        score += 10
    else:
        feedback_parts.append("Warning: File timestamp indicates it was not created during this task")

    # 3. Geometry Type (20 pts)
    # pyshp: 5 is Polygon, 15 is PolygonZ. 
    # Depending on tool it might be 5.
    geom_type = analysis.get('geometry_type')
    if geom_type in [5, 15, 'Polygon', 'PolygonZ']:
        score += 20
        feedback_parts.append("Correct geometry type (Polygon)")
    else:
        feedback_parts.append(f"Incorrect geometry type: {geom_type}")

    # 4. Grid Dimensions (20 pts)
    # 20x20 degree grid over 360x180 world = 18x9 = 162 cells.
    # Allow some variation if they used a different extent but roughly correct.
    feature_count = analysis.get('feature_count', 0)
    if expected_min_features <= feature_count <= expected_max_features:
        score += 20
        feedback_parts.append(f"Grid dimensions correct ({feature_count} cells)")
    else:
        feedback_parts.append(f"Incorrect grid cell count: {feature_count} (Expected {expected_min_features}-{expected_max_features})")

    # 5. Spatial Join / Count Analysis (30 pts)
    # Sum of counts should roughly equal total cities.
    sum_count = analysis.get('sum_count_value', 0)
    lower_bound = expected_total_cities - cities_tolerance
    
    # Upper bound can be higher if points on borders are double counted (unlikely but possible)
    # or significantly lower if grid doesn't cover everything.
    
    if sum_count >= lower_bound:
        score += 30
        feedback_parts.append(f"City counts verified (Sum: {sum_count})")
    elif sum_count > 0:
        score += 15
        feedback_parts.append(f"Partial credit: Counts found but total ({sum_count}) is lower than expected ({expected_total_cities})")
    else:
        feedback_parts.append("No valid city count field found in output")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }