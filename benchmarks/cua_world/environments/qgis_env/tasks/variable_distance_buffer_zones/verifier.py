#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_variable_distance_buffer_zones(traj, env_info, task_info):
    """
    Verify that variable distance buffers were created correctly.
    
    Criteria:
    1. Output file exists and was created during task (20 pts)
    2. Valid GeoJSON with 3 features (20 pts)
    3. Feature areas show significant variation (indicating variable distance used) (30 pts)
    4. Feature areas match expected magnitudes for 30m, 80m, 150m buffers (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Retrieve result file
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
    
    # 1. Check file existence and creation
    if result.get("output_exists") and result.get("file_created_during_task"):
        score += 20
        feedback_parts.append("Output file created successfully.")
    elif result.get("output_exists"):
        score += 10
        feedback_parts.append("Output file exists but timestamp check failed (pre-existing?).")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
        
    analysis = result.get("analysis", {})
    
    # 2. Check GeoJSON validity and count
    if analysis.get("valid_geojson"):
        feat_count = analysis.get("feature_count", 0)
        if feat_count == 3:
            score += 20
            feedback_parts.append("Correct feature count (3).")
        else:
            score += 5
            feedback_parts.append(f"Incorrect feature count: {feat_count} (expected 3).")
    else:
        feedback_parts.append("Invalid GeoJSON content.")
        
    # 3. Check for variable sizing
    # If the user used a fixed buffer, all areas would be roughly equal
    if analysis.get("is_variable"):
        score += 30
        feedback_parts.append("Variable buffer sizes detected.")
    else:
        feedback_parts.append("Buffers appear to be fixed size (areas are uniform). Did you use the attribute field?")
        
    # 4. Check hierarchy/accuracy
    if analysis.get("area_hierarchy_correct"):
        score += 30
        feedback_parts.append("Buffer areas match expected values for 30m, 80m, and 150m radii.")
    else:
        areas = analysis.get("areas", [])
        feedback_parts.append(f"Buffer areas do not match expected magnitudes. Found approx: {[int(a) for a in areas]}")
        
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }