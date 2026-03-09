#!/usr/bin/env python3
"""Verifier for heatmap_kde_population task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_heatmap_kde_population(traj, env_info, task_info):
    """
    Verify that a kernel density heatmap was generated from population data.

    Scoring (100 points):
    - Raster output exists: 15 pts
    - Raster is valid (readable by GDAL): 15 pts
    - Raster has reasonable dimensions (>10x10): 15 pts
    - Raster contains data (max value > 0): 20 pts
    - File size is reasonable (>10KB): 10 pts
    - File was created during task: 10 pts
    - Project file saved: 15 pts

    Pass threshold: 60 points (Must have valid raster with data)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    min_size = metadata.get('min_raster_size_bytes', 10240)

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
    
    raster_analysis = result.get('raster_analysis', {})

    # Criterion 1: Raster exists (15 pts)
    if result.get('raster_exists', False):
        score += 15
        subscores["exists"] = True
        feedback_parts.append("Raster file found")
    else:
        subscores["exists"] = False
        feedback_parts.append("Raster file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Valid Raster (15 pts)
    if raster_analysis.get('valid', False):
        score += 15
        subscores["valid"] = True
        feedback_parts.append(f"Valid GeoTIFF ({raster_analysis.get('driver', 'Unknown')})")
    else:
        subscores["valid"] = False
        feedback_parts.append("Invalid or corrupted raster file")

    # Criterion 3: Non-degenerate dimensions (15 pts)
    width = raster_analysis.get('width', 0)
    height = raster_analysis.get('height', 0)
    if width > 10 and height > 10:
        score += 15
        subscores["dimensions"] = True
        feedback_parts.append(f"Dimensions: {width}x{height}")
    else:
        subscores["dimensions"] = False
        feedback_parts.append(f"Raster dimensions too small: {width}x{height}")

    # Criterion 4: Contains Density Data (20 pts)
    # A heatmap of population should have positive values. 
    # If unweighted or wrong field, values might be low, but > 0.
    max_val = raster_analysis.get('max_value', 0)
    if max_val > 0:
        score += 20
        subscores["has_data"] = True
        feedback_parts.append(f"Contains data (Max density: {max_val:.2f})")
    else:
        subscores["has_data"] = False
        feedback_parts.append("Raster appears empty (Max value <= 0)")

    # Criterion 5: Reasonable File Size (10 pts)
    file_size = result.get('raster_size_bytes', 0)
    if file_size >= min_size:
        score += 10
        subscores["size_ok"] = True
    else:
        subscores["size_ok"] = False
        feedback_parts.append(f"File size suspiciously small ({file_size} bytes)")

    # Criterion 6: Created During Task (10 pts)
    if result.get('created_during_task', False):
        score += 10
        subscores["fresh"] = True
    else:
        subscores["fresh"] = False
        feedback_parts.append("File not modified during task execution")

    # Criterion 7: Project Saved (15 pts)
    if result.get('project_exists', False):
        score += 15
        subscores["project_saved"] = True
        feedback_parts.append("Project file saved")
    else:
        subscores["project_saved"] = False
        feedback_parts.append("Project file NOT saved")

    # Pass logic: Must exist, be valid, have data, and meaningful dimensions
    passed = (subscores.get("exists") and 
              subscores.get("valid") and 
              subscores.get("has_data") and 
              score >= 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }