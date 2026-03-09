#!/usr/bin/env python3
"""Verifier for extract_index_contours_elevation task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_extract_index_contours_elevation(traj, env_info, task_info):
    """
    Verify that index contours (multiples of 100m) were extracted correctly.

    Scoring (100 points):
    - File exists and created during task: 10 points
    - Valid GeoJSON structure: 10 points
    - Geometry is LineString/MultiLineString: 10 points
    - Elevation field exists: 15 points
    - Index Logic (All values % 100 == 0): 35 points
    - Data Authenticity (Values in reasonable SRTM range): 20 points

    Pass threshold: 75 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    logger.info(f"Task result: {result}")

    score = 0
    feedback_parts = []
    subscores = {}

    analysis = result.get('analysis', {})

    # Criterion 1: File Existence & Creation (10 pts)
    if result.get('file_exists', False):
        if result.get('created_during_task', True):
            score += 10
            subscores["file_valid"] = True
            feedback_parts.append("Output file created successfully")
        else:
            score += 5
            subscores["file_valid"] = True
            feedback_parts.append("Output file exists but timestamp suggests pre-existence")
    else:
        subscores["file_valid"] = False
        feedback_parts.append("Output file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Valid GeoJSON (10 pts)
    if analysis.get('valid', False):
        score += 10
        feedback_parts.append("Valid GeoJSON")
    else:
        feedback_parts.append("Invalid GeoJSON content")

    # Criterion 3: Geometry Type (10 pts)
    if analysis.get('all_lines', False):
        score += 10
        subscores["geometry_valid"] = True
        feedback_parts.append("Correct Line geometries")
    else:
        subscores["geometry_valid"] = False
        feedback_parts.append("Geometry mismatch (expected Lines)")

    # Criterion 4: Elevation Field (15 pts)
    if analysis.get('elev_field_found', False):
        score += 15
        fname = analysis.get('elev_field_name', 'unknown')
        feedback_parts.append(f"Elevation field found ('{fname}')")
    else:
        feedback_parts.append("No elevation attribute field found")

    # Criterion 5: Index Logic (35 pts) - CRITICAL
    # We expect ONLY multiples of 100.
    # If mixed (some 100, some not), user likely skipped selection step.
    if analysis.get('all_index_contours', False) and analysis.get('feature_count', 0) > 0:
        score += 35
        subscores["index_logic"] = True
        feedback_parts.append("Correctly filtered for index contours (multiples of 100)")
    elif analysis.get('mixed_contours', True):
        # Did they just export all 20m contours?
        if analysis.get('all_base_contours', False):
            feedback_parts.append("Failed to filter: File contains all 20m contours, not just index contours")
        else:
            feedback_parts.append("Failed filter: Output contains non-index contours")
    elif analysis.get('feature_count', 0) == 0:
        feedback_parts.append("File is empty (no features)")
    else:
        feedback_parts.append("Incorrect elevation values")

    # Criterion 6: Data Authenticity (20 pts)
    # Check if values are within the source DEM range (approx 800-1800m for srtm_41_19)
    min_val = analysis.get('min_val', 0)
    max_val = analysis.get('max_val', 0)
    
    # Broad range check to ensure they didn't just create dummy data (e.g., 0-100)
    if min_val >= 50 and max_val <= 3000 and max_val > min_val:
        score += 20
        feedback_parts.append(f"Elevation values in valid range ({min_val}m - {max_val}m)")
    elif analysis.get('feature_count', 0) > 0:
        feedback_parts.append(f"Elevation values suspicious ({min_val}m - {max_val}m)")

    passed = score >= 75 and subscores.get("index_logic", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }