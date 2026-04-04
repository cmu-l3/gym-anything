#!/usr/bin/env python3
"""
Verifier for clip_countries_by_extent task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_clip_countries_by_extent(traj, env_info, task_info):
    """
    Verify that the user clipped the world countries layer to the European extent.
    
    Scoring Criteria (100 points total):
    - File exists and is new: 20 pts
    - Valid GeoJSON structure: 10 pts
    - Feature count is reasonable (15-55): 15 pts
    - All geometries are Polygons: 10 pts
    - Major European countries present (>=4): 20 pts
    - Non-European countries absent (0): 15 pts
    - Filename matches exactly: 10 pts
    
    Pass Threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Retrieve result
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
    
    # 1. File Existence and Timestamp (20 pts)
    file_exists = result.get("file_exists", "false")
    file_new = result.get("file_new", "false")
    
    if file_exists == "true":
        if file_new == "true":
            score += 20
            feedback_parts.append("Output file created successfully")
        else:
            score += 10
            feedback_parts.append("Output file exists but was not created during this session (stale?)")
    elif file_exists == "true_alt":
        score += 5
        feedback_parts.append("A file was created but with the WRONG filename")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # Analysis Data
    analysis = result.get("analysis", {})
    
    # 2. Valid GeoJSON (10 pts)
    if analysis.get("valid_geojson", False):
        score += 10
        feedback_parts.append("Valid GeoJSON")
    else:
        feedback_parts.append("Invalid GeoJSON content")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    # 3. Filename exact match (10 pts)
    # Already checked in step 1 partially, but if we are here, file_exists is true or true_alt
    if file_exists == "true":
        score += 10
        feedback_parts.append("Filename correct")
    else:
        feedback_parts.append("Filename incorrect")

    # 4. Feature Count (15 pts)
    # Natural Earth 110m clipped to Europe usually has around 30-45 features depending on exact clip
    count = analysis.get("feature_count", 0)
    if 15 <= count <= 65:
        score += 15
        feedback_parts.append(f"Feature count reasonable ({count})")
    else:
        feedback_parts.append(f"Feature count suspicious ({count}) - expected 15-65")

    # 5. Geometry Type (10 pts)
    if analysis.get("all_polygons", False):
        score += 10
        feedback_parts.append("Geometries are polygons")
    else:
        feedback_parts.append("Some geometries are not polygons")

    # 6. Content Check: Europe Present (20 pts)
    found_europe_count = analysis.get("found_europe_count", 0)
    if found_europe_count >= 4:
        score += 20
        feedback_parts.append(f"European countries found ({found_europe_count})")
    elif found_europe_count >= 1:
        score += 10
        feedback_parts.append(f"Few European countries found ({found_europe_count})")
    else:
        feedback_parts.append("No major European countries found")

    # 7. Content Check: Rest of World Absent (15 pts)
    found_forbidden_count = analysis.get("found_forbidden_count", 0)
    if found_forbidden_count == 0:
        score += 15
        feedback_parts.append("No non-European countries found")
    else:
        forbidden_list = analysis.get("found_forbidden_list", [])
        feedback_parts.append(f"Found non-European countries: {', '.join(forbidden_list)}")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }