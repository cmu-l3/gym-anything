#!/usr/bin/env python3
"""
Verifier for georeference_map_with_saved_gcps task.
"""

import json
import tempfile
import os
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_georeference_map_with_saved_gcps(traj, env_info, task_info):
    """
    Verify that the map was georeferenced correctly.
    
    Scoring (100 points):
    - Output file exists and is a valid TIFF: 20 points
    - File created during task: 10 points
    - CRS is EPSG:4326: 20 points
    - Origin (Top-Left) is correct: 25 points
    - Pixel resolution is correct: 15 points
    - Application was running: 10 points
    
    Pass threshold: 65 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_origin_x = metadata.get('expected_origin_x', -122.5)
    expected_origin_y = metadata.get('expected_origin_y', 37.8)
    expected_pixel_size_x = metadata.get('expected_pixel_size_x', 0.0001)
    tolerance = metadata.get('tolerance_degrees', 0.0005)

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
    
    file_meta = result.get('metadata', {})
    
    # Criterion 1: File Exists & Valid (20 pts)
    if result.get('file_exists', False) and file_meta.get('valid_tiff', False):
        score += 20
        feedback_parts.append("Valid GeoTIFF created")
    elif result.get('file_exists', False):
        score += 10
        feedback_parts.append("File exists but validation failed")
    else:
        feedback_parts.append("Output file not found")
        # Critical failure
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    # Criterion 2: Created During Task (10 pts)
    if result.get('file_created_during_task', False):
        score += 10
        feedback_parts.append("File created during task session")
    else:
        feedback_parts.append("File timestamp indicates it wasn't created in this session")
        
    # Criterion 3: Correct CRS (20 pts)
    crs = file_meta.get('crs', '').upper()
    if '4326' in crs or 'WGS 84' in file_meta.get('projection_wkt', ''):
        score += 20
        feedback_parts.append("Correct CRS (EPSG:4326)")
    else:
        feedback_parts.append(f"Incorrect CRS: {crs}")
        
    # Criterion 4: Origin Accuracy (25 pts)
    actual_origin_x = file_meta.get('origin_x', 0)
    actual_origin_y = file_meta.get('origin_y', 0)
    
    dist_x = abs(actual_origin_x - expected_origin_x)
    dist_y = abs(actual_origin_y - expected_origin_y)
    
    if dist_x < tolerance and dist_y < tolerance:
        score += 25
        feedback_parts.append(f"Origin correct ({actual_origin_x:.4f}, {actual_origin_y:.4f})")
    else:
        feedback_parts.append(f"Origin offset too large (Diff: {dist_x:.5f}, {dist_y:.5f})")
        
    # Criterion 5: Resolution Accuracy (15 pts)
    actual_px_x = file_meta.get('pixel_size_x', 0)
    # Resolution should be close to 0.0001
    # Allow 10% variance
    if abs(actual_px_x - expected_pixel_size_x) < (expected_pixel_size_x * 0.2):
        score += 15
        feedback_parts.append(f"Resolution correct ({actual_px_x:.6f})")
    else:
        feedback_parts.append(f"Resolution incorrect ({actual_px_x:.6f})")
        
    # Criterion 6: App Running (10 pts)
    if result.get('app_was_running', False):
        score += 10
        feedback_parts.append("QGIS was running")
        
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }