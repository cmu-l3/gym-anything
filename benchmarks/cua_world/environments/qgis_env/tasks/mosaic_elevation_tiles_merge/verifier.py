#!/usr/bin/env python3
"""Verifier for mosaic_elevation_tiles_merge task."""

import json
import tempfile
import os
import logging
import math

logger = logging.getLogger(__name__)

def verify_mosaic_elevation_tiles_merge(traj, env_info, task_info):
    """
    Verify that two elevation tiles were successfully merged into a single mosaic.
    
    Scoring (100 points):
    - Output file exists: 20 points
    - Valid GeoTIFF format: 10 points
    - Correct spatial extent (covers both inputs): 30 points
    - Data values preserved (min/max range): 20 points
    - Correct CRS (EPSG:4326): 10 points
    - Single band output: 10 points
    
    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}
    
    metadata = task_info.get('metadata', {})
    expected_extent = metadata.get('expected_extent', [-122.5, 37.5, -121.5, 38.0]) # [minx, miny, maxx, maxy]
    
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
    
    analysis = result.get('analysis', {})
    
    # 1. File Exists (20 pts)
    if result.get('file_exists', False):
        score += 20
        feedback_parts.append("Output file found")
    else:
        feedback_parts.append("Output file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Valid GeoTIFF (10 pts)
    if analysis.get('valid_geotiff', False):
        score += 10
        feedback_parts.append("Valid GeoTIFF format")
    else:
        feedback_parts.append("Invalid or unrecognized file format")
        
    # 3. Spatial Extent Check (30 pts)
    # Expected: [-122.5, 37.5, -121.5, 38.0]
    bbox = analysis.get('bbox', [0,0,0,0]) # [minx, miny, maxx, maxy]
    
    # Tolerances for floating point comparisons
    tol = 0.001
    
    # Check MinX (should be -122.5)
    min_x_ok = abs(bbox[0] - expected_extent[0]) < tol
    # Check MaxX (should be -121.5 - i.e. extended to cover East tile)
    max_x_ok = abs(bbox[2] - expected_extent[2]) < tol
    # Check MinY/MaxY
    y_ok = abs(bbox[1] - expected_extent[1]) < tol and abs(bbox[3] - expected_extent[3]) < tol
    
    if min_x_ok and max_x_ok and y_ok:
        score += 30
        feedback_parts.append("Correct spatial extent (covers both tiles)")
    elif min_x_ok and not max_x_ok:
        score += 5
        feedback_parts.append("Extent matches West tile only (did not merge East?)")
    elif not min_x_ok and max_x_ok:
        score += 5
        feedback_parts.append("Extent matches East tile only (did not merge West?)")
    else:
        feedback_parts.append(f"Incorrect extent: {bbox}")

    # 4. Value Range Check (20 pts)
    # West tile: 0-500. East tile: 500-1000.
    # Merged should be approx 0-1000.
    min_val = analysis.get('min_val', 0)
    max_val = analysis.get('max_val', 0)
    
    if min_val < 100 and max_val > 900:
        score += 20
        feedback_parts.append(f"Data values preserved (range {min_val:.1f} to {max_val:.1f})")
    elif max_val < 600:
        feedback_parts.append("Max value too low - seems to contain only West tile")
    elif min_val > 400:
        feedback_parts.append("Min value too high - seems to contain only East tile")
    else:
        # Partial points for valid data
        score += 5
        feedback_parts.append(f"Data values exist but range unexpected: {min_val:.1f}-{max_val:.1f}")

    # 5. CRS Check (10 pts)
    crs_auth = analysis.get('crs_auth', '')
    if '4326' in crs_auth:
        score += 10
        feedback_parts.append("Correct CRS (EPSG:4326)")
    else:
        feedback_parts.append(f"Incorrect or missing CRS: {crs_auth}")
        
    # 6. Band Count (10 pts)
    if analysis.get('band_count', 0) == 1:
        score += 10
        feedback_parts.append("Correct band count (1)")
    else:
        feedback_parts.append(f"Incorrect band count: {analysis.get('band_count')}")

    # Check timestamps for anti-gaming (file must be created during task)
    if not result.get('file_created_during_task', False):
        score = 0
        feedback_parts = ["FAIL: Output file timestamp indicates pre-existing file or copy"]

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }