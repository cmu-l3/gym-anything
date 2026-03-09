#!/usr/bin/env python3
"""
Verifier for select_by_location_export task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_select_by_location_export(traj, env_info, task_info):
    """
    Verify the spatial selection and export task.
    
    Criteria:
    1. Output shapefile exists (10 pts)
    2. File created during task (5 pts)
    3. Valid shapefile with Point geometry (10 pts)
    4. Feature count reasonable for African cities (~20-50) (15 pts)
    5. Contains known African cities (20 pts)
    6. Does NOT contain known non-African cities (15 pts)
    7. Geographic bounds valid for Africa (15 pts)
    8. VLM: Visual confirmation of workflow (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    min_features = metadata.get('min_features', 15)
    max_features = metadata.get('max_features', 55)

    score = 0
    feedback_parts = []
    
    # 1. Load result JSON from container
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
            
    analysis = result.get('analysis', {})
    
    # Criterion 1: Output exists
    if result.get('output_exists'):
        score += 10
        feedback_parts.append("Output shapefile exists")
    else:
        return {"passed": False, "score": 0, "feedback": "Output shapefile not found"}

    # Criterion 2: Freshness
    if result.get('file_created_during_task'):
        score += 5
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File exists but timestamp indicates it wasn't created in this session")

    # Criterion 3: Valid Shapefile / Geometry
    if analysis.get('valid_shapefile'):
        geo_type = analysis.get('geometry_type', 'Unknown')
        if 'Point' in geo_type:
            score += 10
            feedback_parts.append(f"Valid Point shapefile ({geo_type})")
        else:
            feedback_parts.append(f"Valid shapefile but wrong geometry: {geo_type} (expected Point)")
    else:
        feedback_parts.append("Invalid or unreadable shapefile")

    # Criterion 4: Feature Count
    count = analysis.get('feature_count', 0)
    if min_features <= count <= max_features:
        score += 15
        feedback_parts.append(f"Feature count correct ({count})")
    else:
        feedback_parts.append(f"Feature count out of range: {count} (expected {min_features}-{max_features})")

    # Criterion 5: Known Cities (Positive)
    found_cities = analysis.get('cities_found', [])
    if len(found_cities) >= 3:
        score += 20
        feedback_parts.append(f"Found required African cities: {', '.join(found_cities[:3])}...")
    elif len(found_cities) > 0:
        score += 10
        feedback_parts.append(f"Found some African cities: {', '.join(found_cities)}")
    else:
        feedback_parts.append("No reference African cities found")

    # Criterion 6: Forbidden Cities (Negative)
    forbidden_found = analysis.get('cities_forbidden_found', [])
    if len(forbidden_found) == 0 and result.get('output_exists'):
        score += 15
        feedback_parts.append("No non-African cities found")
    else:
        feedback_parts.append(f"Found non-African cities (Selection likely wrong): {', '.join(forbidden_found)}")
        
    # Criterion 7: Bounding Box
    if analysis.get('bbox_valid'):
        score += 15
        feedback_parts.append("Geographic bounds match Africa")
    else:
        feedback_parts.append("Geographic bounds do not match Africa")

    # Criterion 8: VLM Verification
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    vlm_prompt = (
        "Analyze these screenshots of a GIS task (gvSIG Desktop).\n"
        "The user should have:\n"
        "1. Selected countries in Africa (yellow/highlighted polygons).\n"
        "2. Used a selection tool (like 'Select by Layer' or spatial query dialog).\n"
        "3. Exported the selected cities.\n\n"
        "Do you see evidence of selection (highlighted items) and any export dialogs? "
        "Return JSON: {\"selection_visible\": bool, \"dialog_visible\": bool}"
    )
    
    vlm_result = query_vlm(images=frames + [final], prompt=vlm_prompt)
    
    vlm_score = 0
    if isinstance(vlm_result, dict):
        if vlm_result.get("selection_visible"):
            vlm_score += 5
        if vlm_result.get("dialog_visible"):
            vlm_score += 5
    
    score += vlm_score
    if vlm_score > 0:
        feedback_parts.append("VLM verified workflow steps")

    passed = score >= 60 and result.get('output_exists') and analysis.get('valid_shapefile')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }