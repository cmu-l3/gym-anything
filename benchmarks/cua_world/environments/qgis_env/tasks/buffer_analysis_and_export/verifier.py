#!/usr/bin/env python3
"""Verifier for buffer_analysis_and_export task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_buffer_analysis_and_export(traj, env_info, task_info):
    """
    Verify that buffer analysis was performed and exported correctly.

    Scoring (100 points):
    - Output file exists at expected path: 15 points
    - File is valid GeoJSON: 15 points
    - Correct feature count (3 buffers for 3 points): 25 points
    - All features are polygons (buffer output): 20 points
    - All geometries are valid (non-degenerate): 15 points
    - File is new (not pre-existing): 10 points

    Pass threshold: 60 points
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

    # Criterion 2: Valid GeoJSON (15 pts)
    if result.get('file_valid_geojson', False):
        score += 15
        subscores["valid_geojson"] = True
        feedback_parts.append("Valid GeoJSON format")
    else:
        subscores["valid_geojson"] = False
        feedback_parts.append("Invalid GeoJSON format")

    # Criterion 3: Correct feature count (25 pts)
    feature_count = result.get('feature_count', 0)
    if feature_count == expected_feature_count:
        score += 25
        subscores["correct_count"] = True
        feedback_parts.append(f"Correct feature count: {feature_count}")
    elif feature_count > 0:
        # Partial credit for some features
        partial = int(15 * (feature_count / expected_feature_count))
        score += min(partial, 15)
        subscores["correct_count"] = False
        feedback_parts.append(f"Feature count: {feature_count} (expected {expected_feature_count})")
    else:
        subscores["correct_count"] = False
        feedback_parts.append("No features in output")

    # Criterion 4: All features are polygons (20 pts)
    if result.get('all_polygons', False):
        score += 20
        subscores["all_polygons"] = True
        feedback_parts.append("All features are polygons (buffer shapes)")
    else:
        subscores["all_polygons"] = False
        feedback_parts.append("Not all features are polygons")

    # Criterion 5: Valid geometries (15 pts)
    if result.get('has_valid_geometries', False):
        score += 15
        subscores["valid_geometries"] = True
        feedback_parts.append("All geometries valid")
    else:
        subscores["valid_geometries"] = False
        feedback_parts.append("Some geometries invalid or empty")

    # Criterion 6: New file created (not pre-existing) (10 pts)
    initial = result.get('initial_export_count', 0)
    current = result.get('current_export_count', 0)
    if current > initial:
        score += 10
        subscores["new_file"] = True
        feedback_parts.append("New export file created")
    else:
        subscores["new_file"] = False
        feedback_parts.append("No new export files detected")

    passed = score >= 60 and subscores.get("file_exists", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
