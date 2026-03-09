#!/usr/bin/env python3
"""Verifier for generate_city_blocks_from_roads task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_generate_city_blocks_from_roads(traj, env_info, task_info):
    """
    Verify that city blocks were generated from roads and area calculated.

    Scoring (100 points):
    - Output file exists: 10 points
    - File is valid GeoJSON: 10 points
    - Correct geometry type (Polygon): 20 points
    - Correct feature count (2 blocks, ignoring dangles): 20 points
    - 'area_ha' field created: 20 points
    - Area calculation accuracy: 20 points

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_count = metadata.get('expected_feature_count', 2)
    min_area = metadata.get('min_area_ha', 3.0)
    max_area = metadata.get('max_area_ha', 5.0)

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

    # Criterion 1: File exists (10 pts)
    if result.get('file_exists', False):
        score += 10
        subscores["file_exists"] = True
        feedback_parts.append("Output file found")
    else:
        subscores["file_exists"] = False
        feedback_parts.append("Output file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Valid GeoJSON (10 pts)
    if analysis.get('valid', False):
        score += 10
        subscores["valid_geojson"] = True
    else:
        subscores["valid_geojson"] = False
        feedback_parts.append("Invalid GeoJSON or analysis failed")

    # Criterion 3: Geometry Type (20 pts)
    if analysis.get('all_polygons', False):
        score += 20
        subscores["geometry"] = True
        feedback_parts.append("All features are Polygons")
    else:
        subscores["geometry"] = False
        feedback_parts.append("Geometry mismatch (expected Polygons)")

    # Criterion 4: Feature Count (20 pts)
    count = analysis.get('feature_count', 0)
    if count == expected_count:
        score += 20
        subscores["count"] = True
        feedback_parts.append(f"Correct block count: {count}")
    else:
        subscores["count"] = False
        feedback_parts.append(f"Block count: {count} (expected {expected_count})")
        if count == 0:
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 5: Field Existence (20 pts)
    if analysis.get('has_area_field', False):
        score += 20
        subscores["field"] = True
        feedback_parts.append("'area_ha' field found")
    else:
        subscores["field"] = False
        feedback_parts.append("'area_ha' field missing")

    # Criterion 6: Calculation Accuracy (20 pts)
    values = analysis.get('area_values', [])
    if values:
        # Check if values are within plausible range (approx 3.9 ha)
        valid_values = [v for v in values if min_area <= v <= max_area]
        if len(valid_values) == len(values):
            score += 20
            subscores["accuracy"] = True
            feedback_parts.append("Area calculations correct")
        elif len(valid_values) > 0:
            score += 10
            subscores["accuracy"] = False
            feedback_parts.append(f"Some area values out of range ({min_area}-{max_area})")
        else:
            subscores["accuracy"] = False
            feedback_parts.append(f"Area values incorrect (Got {values[:2]}...)")
    else:
        subscores["accuracy"] = False
        feedback_parts.append("No area values to check")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }