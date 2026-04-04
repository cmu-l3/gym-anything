#!/usr/bin/env python3
"""
Verifier for dissolve_countries_by_continent task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dissolve_countries(traj, env_info, task_info):
    """
    Verify the agent successfully dissolved countries by continent.
    
    Scoring Criteria (Total 100):
    1. Output file exists (15 pts)
    2. File is valid GeoJSON (15 pts)
    3. Feature count is correct (5-9 features) (20 pts)
    4. Geometry type is Polygon/MultiPolygon (15 pts)
    5. Continent attribute field exists (15 pts)
    6. Expected continent names are present (10 pts)
    7. File was created during task session (10 pts)
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Metrics
    file_exists = result.get("file_exists", False)
    valid_geojson = result.get("is_valid_geojson", False)
    feature_count = result.get("feature_count", 0)
    geometry_type = result.get("geometry_type", "unknown")
    has_field = result.get("has_continent_field", False)
    found_continents = result.get("found_continents", [])
    created_fresh = result.get("file_created_during_task", False)

    # 3. Scoring Logic
    score = 0
    feedback = []

    # Criterion 1: File Exists
    if file_exists:
        score += 15
        feedback.append("Output file found.")
    else:
        feedback.append("Output file not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: Valid GeoJSON
    if valid_geojson:
        score += 15
        feedback.append("Valid GeoJSON format.")
    else:
        feedback.append("Output is not a valid GeoJSON.")
        # If it's not valid JSON, we can't really check the rest reliably
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Criterion 3: Feature Count (The core logic check)
    # Expected: ~7 continents. Allow 5-9 to account for data variations (e.g. "Seven seas", nulls)
    # If count is ~177, they didn't dissolve (score 0 for this).
    # If count is 1, they dissolved without field (score 0 for this).
    if 5 <= feature_count <= 9:
        score += 20
        feedback.append(f"Feature count correct ({feature_count}).")
    else:
        feedback.append(f"Incorrect feature count: {feature_count}. Expected 5-9 features.")
        if feature_count > 150:
             feedback.append("It appears you saved the original layer without dissolving.")
        elif feature_count == 1:
             feedback.append("It appears you dissolved all features instead of by CONTINENT.")

    # Criterion 4: Geometry Type
    if "Polygon" in geometry_type:
        score += 15
        feedback.append("Geometry type correct (Polygon/MultiPolygon).")
    else:
        feedback.append(f"Incorrect geometry type: {geometry_type}.")

    # Criterion 5: Attribute Field Preserved
    if has_field:
        score += 15
        feedback.append("Continent field preserved.")
    else:
        feedback.append("Continent attribute field missing in output.")

    # Criterion 6: Content Verification
    expected_continents = ["Africa", "Asia", "Europe", "North America", "South America", "Oceania"]
    matches = 0
    # Normalize for comparison
    found_normalized = [str(c).lower() for c in found_continents]
    for exp in expected_continents:
        if exp.lower() in found_normalized:
            matches += 1
    
    if matches >= 5:
        score += 10
        feedback.append(f"Continent names verified ({matches}/{len(expected_continents)}).")
    elif matches > 0:
        score += 5
        feedback.append(f"Some continent names found ({matches}/{len(expected_continents)}).")
    else:
        feedback.append("No recognizable continent names found in data.")

    # Criterion 7: Anti-gaming (Freshness)
    if created_fresh:
        score += 10
        feedback.append("File created during task session.")
    else:
        feedback.append("File timestamp indicates it was not created during this task.")

    # 4. Final Result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }