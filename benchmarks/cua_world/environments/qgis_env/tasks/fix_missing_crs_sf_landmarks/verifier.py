#!/usr/bin/env python3
"""
Verifier for fix_missing_crs_sf_landmarks task.
"""

import json
import tempfile
import os
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def calculate_distance(p1, p2):
    """Calculate Euclidean distance between two points (lon, lat)."""
    return math.sqrt((p1[0] - p2[0])**2 + (p1[1] - p2[1])**2)

def verify_fix_missing_crs_sf_landmarks(traj, env_info, task_info):
    """
    Verify that the agent assigned the correct CRS and exported to WGS84.
    
    Scoring Criteria:
    1. Output file exists (10 pts)
    2. File is valid GeoJSON (10 pts)
    3. CRS is WGS84 (implied or explicit) (20 pts)
    4. Feature count is correct (10 pts)
    5. Spatial Accuracy (50 pts):
       - Checks if the coordinates actually land in San Francisco.
       - This catches the common error of just "saving as" without assigning CRS first.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get Metadata
    metadata = task_info.get('metadata', {})
    expected_landmarks = metadata.get('landmarks', {})
    
    # Read result
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
    
    # 1. Check File Existence (10 pts)
    if result.get("file_exists", False):
        score += 10
        feedback_parts.append("Output file exists")
    else:
        feedback_parts.append("Output file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    analysis = result.get("analysis", {})
    
    # 2. Check Valid GeoJSON (10 pts)
    if analysis.get("valid_geojson", False):
        score += 10
        feedback_parts.append("Valid GeoJSON")
    else:
        feedback_parts.append("Invalid GeoJSON structure")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. Check Feature Count (10 pts)
    feat_count = analysis.get("feature_count", 0)
    if feat_count == 4:
        score += 10
        feedback_parts.append("Correct feature count (4)")
    else:
        feedback_parts.append(f"Incorrect feature count: {feat_count} (expected 4)")

    # 4. Check CRS (20 pts)
    if analysis.get("crs_is_wgs84", False):
        score += 20
        feedback_parts.append("Output CRS is WGS84")
    else:
        feedback_parts.append("Output CRS is not WGS84")

    # 5. Check Spatial Accuracy (50 pts)
    # This is the critical test for the task
    spatial_passed = analysis.get("spatial_check_passed", False)
    coords = analysis.get("first_feature_coords")
    
    if spatial_passed and coords:
        # Double check against specific landmark if possible
        # Feature 1 is Golden Gate Bridge South: [-122.4783, 37.8199]
        expected_ggb = [-122.4783, 37.8199]
        dist = calculate_distance(coords, expected_ggb)
        
        # Tolerance: 0.001 degrees is roughly 100 meters
        if dist < 0.001:
            score += 50
            feedback_parts.append("Coordinates match Golden Gate Bridge location accurately")
        elif dist < 0.01:
            score += 30
            feedback_parts.append("Coordinates roughly correct but slightly off")
        else:
            score += 10
            feedback_parts.append(f"Coordinates inside SF bounds but offset by {dist:.4f} degrees")
    else:
        error = analysis.get("error")
        if error:
            feedback_parts.append(f"Spatial check failed: {error}")
        else:
            feedback_parts.append("Spatial check failed: Landmarks are not in San Francisco (Check input CRS assignment)")

    # 6. Anti-gaming check
    if not result.get("is_new", False):
        score = 0
        feedback_parts = ["FAIL: Output file was not created during this task session"]

    passed = score >= 60 and spatial_passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }