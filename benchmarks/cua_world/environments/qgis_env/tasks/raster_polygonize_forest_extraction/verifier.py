#!/usr/bin/env python3
"""Verifier for raster_polygonize_forest_extraction task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_raster_polygonize_forest_extraction(traj, env_info, task_info):
    """
    Verify that the raster was polygonized and filtered for Forest class (value 1).

    Scoring (100 points):
    - Output file exists: 20 points
    - Valid GeoJSON: 20 points
    - Correct Geometry (Polygons): 15 points
    - Correct Feature Count (approx 4): 15 points
    - Filtering Correct (Only class 1 present): 30 points

    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_count = metadata.get('expected_feature_count', 4)

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
    subscores = {}
    analysis = result.get('analysis', {})

    # Criterion 1: File Exists (20 pts)
    if result.get('file_exists', False):
        score += 20
        subscores["file_exists"] = True
        feedback_parts.append("Output file found")
    else:
        subscores["file_exists"] = False
        feedback_parts.append("Output file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Valid GeoJSON (20 pts)
    if analysis.get('valid', False):
        score += 20
        subscores["valid_geojson"] = True
        feedback_parts.append("Valid GeoJSON")
    else:
        subscores["valid_geojson"] = False
        feedback_parts.append("Invalid GeoJSON structure")

    # Criterion 3: Correct Geometry (15 pts)
    if analysis.get('all_polygons', False):
        score += 15
        subscores["geometry_type"] = True
        feedback_parts.append("Correct geometry type (Polygon)")
    else:
        subscores["geometry_type"] = False
        feedback_parts.append("Incorrect geometry type (expected Polygon)")

    # Criterion 4: Filtering Correctness (30 pts)
    # This is the most important part - did they filter out Water(2) and Urban(3)?
    correct_class = analysis.get('correct_class_only', False)
    found_classes = analysis.get('found_classes', [])
    
    if correct_class and 1 in found_classes:
        score += 30
        subscores["filtering"] = True
        feedback_parts.append("Filtering correct (only Forest class)")
    elif correct_class and not found_classes:
        # File is empty or no classes found
        subscores["filtering"] = False
        feedback_parts.append("File contains no class data")
    else:
        subscores["filtering"] = False
        feedback_parts.append(f"Filtering incorrect. Found classes: {found_classes} (Expected only 1)")

    # Criterion 5: Feature Count (15 pts)
    count = analysis.get('feature_count', 0)
    if count == expected_count:
        score += 15
        subscores["count"] = True
        feedback_parts.append(f"Correct feature count ({count})")
    elif count > 0:
        # Partial credit if filtering was correct but count is off (e.g. topology differences)
        # If filtering failed (e.g. exported all), count will be much higher (6 total features in generation)
        # 1(4 features) + 2(1 feature background) + 3(1 feature center) = 6 total
        if count == 6:
             feedback_parts.append("Feature count indicates no filtering performed (exported all classes)")
        else:
             score += 10
             feedback_parts.append(f"Feature count {count} (expected {expected_count})")
    else:
        feedback_parts.append("No features found")

    passed = score >= 70 and subscores.get("filtering", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }