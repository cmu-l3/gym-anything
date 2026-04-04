#!/usr/bin/env python3
"""
Verifier for rasterize_vector_to_raster task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rasterize_vector_to_raster(traj, env_info, task_info):
    """
    Verify the rasterization task.
    
    Criteria:
    1. Raster file exists and was created during task (20 pts)
    2. Valid GeoTIFF format (10 pts)
    3. Correct Dimensions/Resolution (approximate) (10 pts)
    4. Correct CRS/Extent (15 pts)
    5. Correct Pixel Values (10.5 and 8.2 present) (25 pts)
    6. QGIS Project saved (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON
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
    
    # Criterion 1: Raster File Exists & Created During Task
    if result.get("raster_exists") and result.get("file_created_during_task"):
        score += 20
        feedback_parts.append("Raster file created")
    elif result.get("raster_exists"):
        score += 10
        feedback_parts.append("Raster exists but timestamp logic failed (old file?)")
    else:
        feedback_parts.append("Raster file NOT found")

    # Criterion 2: Valid GeoTIFF
    if result.get("raster_valid"):
        score += 10
        feedback_parts.append("Valid GeoTIFF")
    else:
        feedback_parts.append("Invalid or unreadable raster")

    # Criterion 3: Dimensions/Resolution
    # Expected: 0.005 deg resolution.
    # Extent is approx 0.6 deg width (122.5 to 121.9). 0.6 / 0.005 = 120 pixels.
    # Allow loose range since extent might vary slightly.
    width = result.get("raster_width", 0)
    height = result.get("raster_height", 0)
    if 50 < width < 500 and 20 < height < 500:
        score += 10
        feedback_parts.append(f"Dimensions reasonable ({width}x{height})")
    else:
        feedback_parts.append(f"Dimensions unexpected ({width}x{height})")

    # Criterion 4: CRS & Extent
    if result.get("raster_crs_valid"):
        score += 5
        feedback_parts.append("CRS valid")
    
    extent = result.get("raster_extent", {})
    # Expect ~ -122.5, 37.5
    xmin = extent.get("xmin", 0)
    ymin = extent.get("ymin", 0)
    if -123 < xmin < -121 and 37 < ymin < 38:
        score += 10
        feedback_parts.append("Extent correct")
    else:
        feedback_parts.append(f"Extent incorrect (xmin:{xmin:.2f}, ymin:{ymin:.2f})")

    # Criterion 5: Correct Pixel Values
    # We expect 10.5 and 8.2 to be burned in
    if result.get("has_expected_values"):
        score += 25
        feedback_parts.append("Burn-in values correct (10.5, 8.2 found)")
    else:
        # Partial credit if at least one found or close
        vals = result.get("unique_values", [])
        feedback_parts.append(f"Expected values not found. Found: {vals[:5]}...")
        if len(vals) > 1:
            score += 5 # At least it's not empty

    # Criterion 6: Project Saved
    if result.get("project_exists"):
        score += 20
        feedback_parts.append("Project saved")
    else:
        feedback_parts.append("Project file not found")

    passed = score >= 60 and result.get("raster_valid")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }