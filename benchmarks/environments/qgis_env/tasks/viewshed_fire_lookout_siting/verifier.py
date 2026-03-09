#!/usr/bin/env python3
"""Verifier for viewshed_fire_lookout_siting task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_viewshed_fire_lookout_siting(traj, env_info, task_info):
    """
    Verify Viewshed Analysis task.

    Scoring (100 points):
    - Output file exists: 20 points
    - Intermediate reprojected file exists: 10 points
    - Valid GeoTIFF format: 10 points
    - Correct CRS (EPSG:32734): 20 points
    - Binary Output (Viewshed map): 20 points
    - Plausible Visibility (not empty, not full): 20 points

    Pass threshold: 70 points
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

    # Criterion 1: Output exists (20 pts)
    if result.get('file_exists', False):
        score += 20
        subscores["file_exists"] = True
        feedback_parts.append("Output file found")
    else:
        subscores["file_exists"] = False
        feedback_parts.append("Output file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Reprojection performed (intermediate file) (10 pts)
    if result.get('reprojected_exists', False):
        score += 10
        subscores["reprojected"] = True
        feedback_parts.append("Intermediate reprojected DEM found")
    else:
        subscores["reprojected"] = False
        feedback_parts.append("Intermediate reprojected DEM NOT found (did you skip reprojection?)")

    # Criterion 3: Valid GeoTIFF (10 pts)
    if analysis.get('valid', False):
        score += 10
        subscores["valid_format"] = True
        feedback_parts.append("Valid GeoTIFF")
    else:
        subscores["valid_format"] = False
        feedback_parts.append("Invalid or corrupted raster file")

    # Criterion 4: Correct CRS (20 pts)
    # EPSG:32734 is WGS 84 / UTM zone 34S
    crs_auth = analysis.get('crs_auth', '')
    is_utm = analysis.get('is_utm_34s', False)
    
    if is_utm or crs_auth == '32734':
        score += 20
        subscores["correct_crs"] = True
        feedback_parts.append("CRS is correct (EPSG:32734)")
    else:
        subscores["correct_crs"] = False
        feedback_parts.append(f"Incorrect CRS: Expected EPSG:32734, got {crs_auth}")

    # Criterion 5: Binary Output (20 pts)
    # A viewshed should be binary (0/1 or 0/255)
    is_binary = analysis.get('is_binary', False)
    unique_count = analysis.get('unique_count', 0)
    
    if is_binary or unique_count <= 5: # Tolerance for minor artifacts
        score += 20
        subscores["binary_content"] = True
        feedback_parts.append("Output is a binary map (viewshed)")
    else:
        subscores["binary_content"] = False
        feedback_parts.append(f"Output appears to be continuous data ({unique_count} unique values), not a viewshed binary map")

    # Criterion 6: Plausible Visibility (20 pts)
    # Should not be empty (0%) and unlikely to be 100% visible in mountains
    visible_ratio = analysis.get('visible_ratio', 0.0)
    
    if 0.001 < visible_ratio < 0.95:
        score += 20
        subscores["plausible_data"] = True
        feedback_parts.append(f"Visibility coverage plausible ({visible_ratio*100:.1f}%)")
    elif visible_ratio <= 0.001:
        # Check if max value is > 0 (maybe it's just very small area)
        if analysis.get('max_val', 0) > 0:
             score += 10
             feedback_parts.append("Very small visible area detected")
        else:
             subscores["plausible_data"] = False
             feedback_parts.append("Map is empty (all 0s)")
    else:
        subscores["plausible_data"] = False
        feedback_parts.append("Map is entirely visible (all 1s) - unlikely for terrain viewshed")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }