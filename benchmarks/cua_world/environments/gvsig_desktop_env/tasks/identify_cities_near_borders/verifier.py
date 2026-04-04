#!/usr/bin/env python3
"""
Verifier for identify_cities_near_borders task.

Task: Export a shapefile of cities within 0.5 degrees of a border.

Verification Criteria:
1. File Creation (20 pts): 'border_cities.shp' exists and created during task.
2. Geometry Check (10 pts): Output must be Point/MultiPoint type.
3. Feature Count (30 pts): Must be a subset of total cities (filtering happened).
   - Expected total cities: ~243
   - Expected border cities: 30-100 range
4. VLM Verification (40 pts): Trajectory shows geoprocessing tools were used.
   - Evidence of "Polygons to lines" or "Buffer" or "Selection by layer" tools.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_identify_cities_near_borders(traj, env_info, task_info):
    """
    Verify the spatial analysis task result.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_cities = metadata.get('min_expected_cities', 30)
    max_cities = metadata.get('max_expected_cities', 100)
    total_cities = metadata.get('expected_total_cities', 243)

    score = 0
    feedback_parts = []
    
    # 1. Load Result JSON
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

    # 2. Check File Existence & Timestamp (20 pts)
    output_exists = result.get('output_exists', False)
    created_during = result.get('file_created_during_task', False)
    
    if output_exists and created_during:
        score += 20
        feedback_parts.append("Output shapefile created successfully")
    elif output_exists:
        score += 10
        feedback_parts.append("Output file exists but timestamp check failed")
    else:
        feedback_parts.append("Output shapefile not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 3. Check Geometry Type (10 pts)
    geo_type = result.get('geometry_type', 'Unknown')
    if geo_type == "Point":
        score += 10
        feedback_parts.append("Correct geometry type (Point)")
    else:
        feedback_parts.append(f"Incorrect geometry type: {geo_type} (expected Point)")

    # 4. Check Feature Count (30 pts)
    count = result.get('feature_count', 0)
    
    # A perfect result should be within range
    if min_cities <= count <= max_cities:
        score += 30
        feedback_parts.append(f"Feature count {count} is within valid range ({min_cities}-{max_cities})")
    # Partial credit if they filtered *something* but got weird results
    elif 0 < count < total_cities:
        score += 15
        feedback_parts.append(f"Feature count {count} indicates filtering occurred, but is outside expected range")
    # No credit if count is 0 (empty) or equal to total (no filtering)
    elif count == total_cities:
        feedback_parts.append(f"Feature count {count} equals total dataset - no filtering was applied")
    else:
        feedback_parts.append(f"Invalid feature count: {count}")

    # 5. VLM Verification (40 pts)
    # Check for evidence of Geoprocessing tools usage
    frames = sample_trajectory_frames(traj, n=8)
    final_frame = get_final_screenshot(traj)
    images = frames + [final_frame] if final_frame else frames
    
    vlm_prompt = (
        "Analyze these screenshots of a GIS workflow in gvSIG Desktop. "
        "The user should be converting countries to lines, buffering them, and selecting cities.\n"
        "1. Do you see the 'Geoprocessing' toolbox or menu open?\n"
        "2. Do you see any 'Buffer' or 'Polygons to lines' dialog?\n"
        "3. Do you see a 'Selection by Layer' or 'Select by spatial location' dialog?\n"
        "4. In the final result, are only SOME city points highlighted/selected (yellow), or is there a new layer of specific points?\n"
        "Return yes/no and a brief reason."
    )
    
    vlm_result = query_vlm(images, vlm_prompt)
    vlm_score = 0
    
    lower_resp = str(vlm_result).lower()
    if "yes" in lower_resp:
        vlm_score = 40
        feedback_parts.append("VLM confirmed geoprocessing workflow")
    else:
        # Fallback: check just for selection evidence
        if "selected" in lower_resp or "yellow" in lower_resp:
            vlm_score = 20
            feedback_parts.append("VLM confirmed selection, but workflow unclear")
        else:
            feedback_parts.append("VLM did not detect geoprocessing workflow")
            
    score += vlm_score

    # Final Pass Logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }