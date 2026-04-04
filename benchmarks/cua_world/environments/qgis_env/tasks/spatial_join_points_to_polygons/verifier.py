#!/usr/bin/env python3
"""Verifier for spatial_join_points_to_polygons task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_spatial_join_points_to_polygons(traj, env_info, task_info):
    """
    Verify that a spatial join was performed and exported correctly.

    Scoring (100 points):
    - Output file exists at expected path: 15 points
    - File is valid GeoJSON FeatureCollection: 10 points
    - Correct feature count (3 joined points): 20 points
    - All features are Point geometries: 10 points
    - Join fields present (area_sqkm or polygon name): 20 points
    - Join is correct (points matched to right polygons): 15 points
    - New file created (not pre-existing): 10 points

    Pass threshold: 55 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_feature_count = metadata.get('expected_feature_count', 3)

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

    # Criterion 1: Output file exists (15 pts)
    file_exists = result.get('file_exists', False)
    if file_exists:
        score += 15
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
        feedback_parts.append("Valid GeoJSON")
    else:
        subscores["valid_geojson"] = False
        feedback_parts.append("Invalid GeoJSON")

    # Criterion 3: Correct feature count (20 pts)
    feature_count = analysis.get('feature_count', 0)
    if feature_count == expected_feature_count:
        score += 20
        subscores["correct_count"] = True
        feedback_parts.append(f"Correct feature count: {feature_count}")
    elif feature_count > 0:
        partial = int(10 * min(feature_count, expected_feature_count) / expected_feature_count)
        score += partial
        subscores["correct_count"] = False
        feedback_parts.append(f"Feature count: {feature_count} (expected {expected_feature_count})")
    else:
        subscores["correct_count"] = False
        feedback_parts.append("No features in output")

    # Criterion 4: All features are points (10 pts)
    if analysis.get('all_points', False):
        score += 10
        subscores["all_points"] = True
        feedback_parts.append("All features are points")
    else:
        subscores["all_points"] = False
        feedback_parts.append("Geometry type mismatch (expected points)")

    # Criterion 5: Join fields present (20 pts)
    has_join = analysis.get('has_join_fields', False)
    if has_join:
        score += 20
        subscores["join_fields"] = True
        details = []
        if analysis.get('has_area_sqkm', False):
            details.append("area_sqkm")
        if analysis.get('has_polygon_name', False):
            details.append("polygon name")
        feedback_parts.append(f"Join fields found: {', '.join(details)}")
    else:
        subscores["join_fields"] = False
        feedback_parts.append("Join fields NOT found (missing polygon attributes)")

    # Criterion 6: Join correctness (15 pts)
    if analysis.get('join_correct', False) and has_join:
        score += 15
        subscores["join_correct"] = True
        feedback_parts.append("Join mapping is correct (points matched to right polygons)")
    elif has_join:
        score += 5
        subscores["join_correct"] = False
        feedback_parts.append("Join fields present but mapping may be incorrect")
    else:
        subscores["join_correct"] = False
        feedback_parts.append("Cannot verify join correctness")

    # Criterion 7: New file created (10 pts)
    initial = result.get('initial_export_count', 0)
    current = result.get('current_export_count', 0)
    if current > initial:
        score += 10
        subscores["new_file"] = True
        feedback_parts.append("New export created")
    else:
        subscores["new_file"] = False
        feedback_parts.append("No new exports detected")

    passed = score >= 55 and subscores.get("file_exists", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
