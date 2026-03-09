#!/usr/bin/env python3
"""
Verifier for road_proximity_clip_analysis task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_road_proximity_clip_analysis(traj, env_info, task_info):
    """
    Verify road proximity analysis result.
    
    Criteria:
    1. Output file exists and was created during task (20 pts)
    2. Valid GeoJSON with Line geometries (20 pts)
    3. 'impact_len' field exists (20 pts)
    4. Data is actually clipped (Total length < 10km) (20 pts)
       - Proves proper buffer & clip sequence
       - Proves use of metric CRS (otherwise degrees would be tiny numbers or huge if reprojected wrongly)
    5. Feature count > 0 (10 pts)
    6. VLM Check / Screenshot existence (10 pts)
    
    Pass threshold: 65 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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
    feedback = []
    
    # Analysis data from export script
    analysis = result.get("analysis", {})
    output_exists = result.get("output_exists", False)
    created_during = result.get("file_created_during_task", False)
    
    # 1. File Existence & Freshness (20 pts)
    if output_exists and created_during:
        score += 20
        feedback.append("Output file created successfully.")
    elif output_exists:
        score += 10
        feedback.append("Output file exists but timestamp is old (re-used?).")
    else:
        feedback.append("Output file not found.")
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # 2. Geometry Validation (20 pts)
    if analysis.get("valid_geojson"):
        score += 10
        if analysis.get("geometry_type_ok"):
            score += 10
            feedback.append("Geometry type is correct (Lines).")
        else:
            feedback.append("Geometry type incorrect (expected Lines).")
    else:
        feedback.append("Invalid GeoJSON.")

    # 3. Field Existence (20 pts)
    if analysis.get("field_exists"):
        score += 20
        feedback.append("Field 'impact_len' found.")
    else:
        feedback.append("Field 'impact_len' missing.")

    # 4. Clip Verification (20 pts)
    # Total length should be small (clipped) vs large (original)
    total_len = analysis.get("total_length", 0)
    is_clipped = analysis.get("is_clipped", False)
    
    if is_clipped:
        score += 20
        feedback.append(f"Roads appear correctly clipped (Total len: {total_len:.2f}m).")
    else:
        if total_len > 20000:
            feedback.append(f"Roads do NOT appear clipped (Total len: {total_len:.2f}m is too large). Did you forget to clip?")
        elif total_len < 1:
            feedback.append(f"Total length is near zero ({total_len}). Check unit/CRS calculation.")
        else:
            feedback.append(f"Clip status uncertain (Total len: {total_len}).")

    # 5. Feature Count (10 pts)
    count = analysis.get("feature_count", 0)
    if count > 0:
        score += 10
        feedback.append(f"Contains {count} features.")
    else:
        feedback.append("Output is empty.")

    # 6. Screenshot / App Running (10 pts)
    # We assume if export ran, app was likely there, but check file existence
    if result.get("screenshot_path"):
        score += 10
        feedback.append("Evidence captured.")

    passed = score >= 65 and is_clipped
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }