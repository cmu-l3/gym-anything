#!/usr/bin/env python3
"""
Verifier for terrain_hillshade_slope_analysis task.
Checks if Hillshade and Slope rasters are generated correctly using statistical properties.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_terrain_hillshade_slope_analysis(traj, env_info, task_info):
    """
    Verify terrain analysis results.
    
    Criteria:
    1. Hillshade file exists and is valid GeoTIFF (20 pts)
    2. Hillshade statistics look correct (0-255 range, variance exists) (20 pts)
    3. Slope file exists and is valid GeoTIFF (20 pts)
    4. Slope statistics look correct (values > 0, reasonable max for terrain) (20 pts)
    5. Project file exists (10 pts)
    6. Files were created during task session (Anti-gaming) (10 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Hillshade Check
    if result.get("hillshade_exists") and result.get("hillshade_valid"):
        score += 20
        stats = result.get("hillshade_stats", {})
        # Hillshade is typically 0-255. A flat raster has std_dev ~0. Real terrain > 0.
        # Mean is usually around 180 for flat, but varies with lighting.
        if 0 <= stats.get("min", -1) and stats.get("max", 256) <= 255 and stats.get("std_dev", 0) > 1:
            score += 20
            feedback_parts.append("Hillshade valid")
        else:
            feedback_parts.append(f"Hillshade stats invalid (std_dev={stats.get('std_dev')})")
    else:
        feedback_parts.append("Hillshade file missing/invalid")

    # 2. Slope Check
    if result.get("slope_exists") and result.get("slope_valid"):
        score += 20
        stats = result.get("slope_stats", {})
        # Slope in degrees. Max should be < 90. Min >= 0.
        # For our synthetic terrain, max slope should be significant (e.g. > 5 degrees)
        if stats.get("min", -1) >= 0 and stats.get("max", 0) > 5 and stats.get("max", 100) <= 90:
            score += 20
            feedback_parts.append("Slope valid")
        else:
            feedback_parts.append(f"Slope stats invalid (max={stats.get('max')})")
    else:
        feedback_parts.append("Slope file missing/invalid")

    # 3. Project Check
    if result.get("project_exists"):
        score += 10
        feedback_parts.append("Project saved")
    else:
        feedback_parts.append("Project missing")

    # 4. Anti-gaming (Timestamp)
    if result.get("timestamp_valid"):
        score += 10
    else:
        feedback_parts.append("Files not modified during task")

    passed = score >= 80  # Requires most components to be correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }