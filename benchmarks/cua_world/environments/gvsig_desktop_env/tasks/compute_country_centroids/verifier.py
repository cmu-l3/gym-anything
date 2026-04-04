#!/usr/bin/env python3
"""
Verifier for compute_country_centroids task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_country_centroids(traj, env_info, task_info):
    """
    Verifies that the agent computed centroids for the countries layer.
    
    Criteria:
    1. Output shapefile exists and was created during the task.
    2. Output contains Point geometries (not polygons).
    3. Feature count matches expected range (~177 for Natural Earth countries).
    4. Coordinates are valid (lat/lon).
    5. VLM confirms UI interaction with geoprocessing tools.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    analysis = result.get('analysis', {})
    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Existence & Freshness (20 pts) ---
    if analysis.get('file_exists'):
        if analysis.get('file_fresh'):
            score += 20
            feedback_parts.append("Output file created successfully.")
        else:
            score += 5
            feedback_parts.append("Output file exists but was NOT modified during task (stale).")
    else:
        feedback_parts.append("Output file 'country_centroids.shp' not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}

    # --- Criterion 2: Geometry Type (20 pts) ---
    # Shape types: 1=Point, 11=PointZ, 21=PointM
    shape_type = analysis.get('shape_type')
    if shape_type in [1, 11, 21]:
        score += 20
        feedback_parts.append("Correct geometry type (Point).")
    else:
        feedback_parts.append(f"Incorrect geometry type: {shape_type} (expected Point).")

    # --- Criterion 3: Feature Count (20 pts) ---
    # Natural Earth countries usually has ~177 features
    count = analysis.get('feature_count', 0)
    expected_min = task_info.get('metadata', {}).get('expected_feature_count_min', 150)
    expected_max = task_info.get('metadata', {}).get('expected_feature_count_max', 200)
    
    if expected_min <= count <= expected_max:
        score += 20
        feedback_parts.append(f"Feature count correct ({count}).")
    elif count > 0:
        score += 5
        feedback_parts.append(f"Feature count mismatch: {count} (expected {expected_min}-{expected_max}).")
    else:
        feedback_parts.append("Output file is empty.")

    # --- Criterion 4: Coordinate Validity (10 pts) ---
    if analysis.get('valid_coords'):
        score += 10
        feedback_parts.append("Coordinates are valid.")
    else:
        feedback_parts.append("Coordinates are invalid/out of bounds.")
        
    # --- Criterion 5: Attribute Preservation (10 pts) ---
    fields = analysis.get('fields', [])
    # Check for common Natural Earth fields
    common_fields = ['NAME', 'ADMIN', 'SOVEREIGNT', 'POP_EST', 'GDP_MD_EST']
    if any(f in fields for f in common_fields):
        score += 10
        feedback_parts.append("Attributes preserved from input.")
    else:
        feedback_parts.append("Original attributes missing.")

    # --- Criterion 6: VLM Verification (20 pts) ---
    # Check trajectory for geoprocessing tool usage
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    images = frames + ([final_img] if final_img else [])
    
    vlm_prompt = (
        "Analyze these screenshots of a gvSIG Desktop session. "
        "The user task was to calculate centroids for country polygons. "
        "1. Do you see any Geoprocessing tool dialog (e.g., 'Centroids', 'Process', 'Toolbox') open? "
        "2. Do you see a new layer (likely points) added to the map over the countries? "
        "Answer 'YES' if you see evidence of geoprocessing or the resulting point layer."
    )
    
    try:
        vlm_res = query_vlm(images, vlm_prompt).strip().lower()
        if "yes" in vlm_res:
            score += 20
            feedback_parts.append("VLM confirmed geoprocessing workflow.")
        else:
            feedback_parts.append("VLM did not see clear evidence of geoprocessing.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Grant partial points if file-based checks passed perfectly
        if score >= 70:
            score += 10 

    passed = score >= 70 and analysis.get('file_fresh') and shape_type in [1, 11, 21]
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }