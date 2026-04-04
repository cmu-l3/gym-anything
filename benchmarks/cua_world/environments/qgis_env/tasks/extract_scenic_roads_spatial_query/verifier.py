#!/usr/bin/env python3
"""
Verifier for extract_scenic_roads_spatial_query task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_scenic_roads(traj, env_info, task_info):
    """
    Verify the agent extracted roads intersecting parks.
    
    Criteria:
    1. Output file exists (10 pts)
    2. Output file is valid GeoJSON (10 pts)
    3. File was created during task (Anti-gaming) (10 pts)
    4. Feature count is reasonable (Roads intersecting parks != 0 and != all roads) (30 pts)
    5. Geometry type is LineString/MultiLineString (Proof of selection, not buffer/polygon overlay) (20 pts)
    6. Attributes preserved (Proof of selection) (20 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Retrieve result file
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
    
    # 1. File Existence
    if result.get("file_exists"):
        score += 10
        feedback_parts.append("Output file found.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    analysis = result.get("analysis", {})
    
    # 2. Validity
    if analysis.get("valid"):
        score += 10
    else:
        return {"passed": False, "score": score, "feedback": f"Invalid GeoJSON: {analysis.get('error')}"}

    # 3. Anti-gaming (Timestamp)
    if result.get("is_new"):
        score += 10
        feedback_parts.append("File created during task.")
    else:
        feedback_parts.append("Warning: File timestamp indicates pre-existence.")

    # 4. Feature Count
    count = analysis.get("count", 0)
    min_count = metadata.get("min_feature_count", 50)
    max_count = metadata.get("max_feature_count", 20000)
    
    if count == 0:
        feedback_parts.append("Output contains zero features.")
    elif min_count <= count <= max_count:
        score += 30
        feedback_parts.append(f"Feature count {count} is within expected range.")
    else:
        feedback_parts.append(f"Feature count {count} outside expected range ({min_count}-{max_count}).")
        score += 10 # Partial credit for getting something

    # 5. Geometry Type (Crucial for identifying 'Selection' vs 'Clip/Buffer')
    # Should be LineString (preserved geometry), not MultiPolygon (clip result)
    geom_types = analysis.get("geometry_types", [])
    valid_types = ["LineString", "MultiLineString"]
    has_valid_geom = any(t in valid_types for t in geom_types)
    has_invalid_geom = any(t not in valid_types and t is not None for t in geom_types)
    
    if has_valid_geom and not has_invalid_geom:
        score += 20
        feedback_parts.append("Correct geometry type (LineString).")
    elif has_valid_geom:
        score += 10
        feedback_parts.append("Mixed geometry types found.")
    else:
        feedback_parts.append(f"Incorrect geometry types: {geom_types}. Expected LineString.")

    # 6. Attributes Preserved
    # Check for standard Natural Earth road attributes like 'type', 'name', 'sov_a3'
    attributes = analysis.get("attributes", [])
    expected_attrs = ["type", "name", "sov_a3", "scalerank"]
    # Check if at least 2 common attributes exist
    matched_attrs = [a for a in expected_attrs if a in attributes]
    if len(matched_attrs) >= 2:
        score += 20
        feedback_parts.append("Original attributes preserved.")
    else:
        feedback_parts.append("Attributes missing or renamed (Clip/Overlay might have been used instead of Select).")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }