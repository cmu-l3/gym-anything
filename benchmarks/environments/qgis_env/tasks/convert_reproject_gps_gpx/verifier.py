#!/usr/bin/env python3
"""
Verifier for convert_reproject_gps_gpx task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_convert_reproject_gps_gpx(traj, env_info, task_info):
    """
    Verify the GPX conversion and reprojection task.
    
    Criteria:
    1. Output GeoPackage exists and was created during task. (20 pts)
    2. File is a valid GeoPackage (readable layers). (20 pts)
    3. CRS is EPSG:3857 (Web Mercator). (30 pts)
    4. Geometry type is Point (not LineString/Track). (15 pts)
    5. Feature count matches input waypoints (5). (15 pts)
    
    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Retrieve result
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
            
    analysis = result.get("analysis", {})
    
    score = 0
    feedback_parts = []
    
    # 1. Check Existence & Freshness (20 pts)
    if analysis.get("exists") and analysis.get("created_during_task"):
        score += 20
        feedback_parts.append("New output file created")
    elif analysis.get("exists"):
        score += 10
        feedback_parts.append("Output file exists (but timestamp uncertain)")
    else:
        feedback_parts.append("Output file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Check Validity (20 pts)
    if analysis.get("valid_format"):
        score += 20
        feedback_parts.append("Valid GeoPackage format")
    else:
        feedback_parts.append("Invalid or unreadable file format")
        
    # 3. Check CRS (30 pts)
    # The analysis script checks for '3857' or metric units
    if analysis.get("crs_is_metric") or "3857" in str(analysis.get("crs", "")):
        score += 30
        feedback_parts.append("Correct CRS (EPSG:3857)")
    else:
        crs_found = analysis.get("crs", "Unknown")
        feedback_parts.append(f"Incorrect CRS: {crs_found} (Expected EPSG:3857)")
        
    # 4. Check Geometry (15 pts)
    geom_type = analysis.get("geometry_type", "Unknown")
    if geom_type == "Point" or geom_type == "MultiPoint":
        score += 15
        feedback_parts.append("Correct geometry type (Point)")
    else:
        feedback_parts.append(f"Incorrect geometry: {geom_type} (Expected Point - did you import Tracks instead of Waypoints?)")
        
    # 5. Check Count (15 pts)
    # Input GPX had 5 waypoints
    count = analysis.get("feature_count", 0)
    if count == 5:
        score += 15
        feedback_parts.append("Correct feature count (5)")
    else:
        feedback_parts.append(f"Incorrect feature count: {count} (Expected 5)")
        
    # Determine Pass/Fail
    # Must have File, Valid Format, and Correct CRS to pass (min 70)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }