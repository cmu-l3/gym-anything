#!/usr/bin/env python3
"""
Verifier for random_sampling_points_export task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_random_sampling_points_export(traj, env_info, task_info):
    """
    Verify random points generation and export.
    
    Scoring (100 pts total):
    - GeoJSON exists & valid: 20 pts
    - Correct feature count (15 pts +/- 1): 20 pts
    - GeoJSON has correct geometry (Points): 10 pts
    - CSV exists: 20 pts
    - CSV has correct row count: 15 pts
    - CSV has coordinate columns: 15 pts
    
    Anti-gaming: Files must be created during task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_count = metadata.get('expected_feature_count', 15)
    
    # Read result from container
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
    
    # 1. GeoJSON Checks
    if result.get("geojson_exists") and result.get("geojson_created_during_task"):
        if result.get("geojson_valid"):
            score += 20
            feedback_parts.append("GeoJSON created and valid")
            
            # Count check
            count = result.get("geojson_feature_count", 0)
            if count == expected_count:
                score += 20
                feedback_parts.append(f"Correct feature count ({count})")
            elif abs(count - expected_count) <= 2:
                score += 10
                feedback_parts.append(f"Feature count close ({count}/{expected_count})")
            else:
                feedback_parts.append(f"Incorrect feature count ({count})")
                
            # Geometry check
            if result.get("geojson_all_points"):
                score += 10
                feedback_parts.append("Geometry type correct")
            else:
                feedback_parts.append("Invalid geometry types found")
                
            # Bounds check (implicit validation of location)
            if result.get("geojson_coords_in_bounds"):
                feedback_parts.append("Coordinates inside expected region")
            else:
                feedback_parts.append("Warning: Some points outside bounds")
        else:
            score += 5
            feedback_parts.append("GeoJSON exists but is invalid")
    else:
        feedback_parts.append("GeoJSON output missing or pre-existing")

    # 2. CSV Checks
    if result.get("csv_exists") and result.get("csv_created_during_task"):
        score += 20
        feedback_parts.append("CSV created")
        
        # Row count
        rows = result.get("csv_row_count", 0)
        if rows == expected_count:
            score += 15
            feedback_parts.append(f"CSV row count correct ({rows})")
        elif abs(rows - expected_count) <= 2:
            score += 8
            feedback_parts.append(f"CSV row count close ({rows})")
            
        # Columns
        if result.get("csv_has_coord_columns"):
            score += 15
            feedback_parts.append("CSV has coordinate columns")
        else:
            feedback_parts.append("CSV missing coordinate headers")
    else:
        feedback_parts.append("CSV output missing or pre-existing")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }