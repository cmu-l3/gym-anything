#!/usr/bin/env python3
"""Verifier for reproject_and_measure_distances task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_reproject_and_measure_distances(traj, env_info, task_info):
    """
    Verify that roads were reprojected, lengths calculated, and CSV exported.

    Scoring (100 points):
    - CSV file exists at expected path: 15 points
    - CSV is valid with correct structure: 10 points
    - Correct row count (2 roads): 15 points
    - Has length field with numeric values: 20 points
    - Length values are positive and plausible: 15 points
    - Both road names present: 10 points
    - Reprojected GeoJSON created: 15 points

    Pass threshold: 55 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_road_count = metadata.get('expected_road_count', 2)

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

    csv_analysis = result.get('csv_analysis', {})

    # Criterion 1: CSV file exists (15 pts)
    csv_exists = result.get('csv_exists', False)
    if csv_exists:
        score += 15
        subscores["csv_exists"] = True
        feedback_parts.append("CSV file found")
    else:
        subscores["csv_exists"] = False
        feedback_parts.append("CSV file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: CSV is valid with correct structure (10 pts)
    if csv_analysis.get('valid', False):
        score += 10
        subscores["csv_valid"] = True
        headers = csv_analysis.get('headers', [])
        feedback_parts.append(f"Valid CSV with headers: {headers[:5]}")
    else:
        subscores["csv_valid"] = False
        feedback_parts.append("CSV parsing failed")

    # Criterion 3: Correct row count (15 pts)
    row_count = csv_analysis.get('row_count', 0)
    if row_count == expected_road_count:
        score += 15
        subscores["correct_count"] = True
        feedback_parts.append(f"Correct road count: {row_count}")
    elif row_count > 0:
        score += 7
        subscores["correct_count"] = False
        feedback_parts.append(f"Road count: {row_count} (expected {expected_road_count})")
    else:
        subscores["correct_count"] = False
        feedback_parts.append("No data rows in CSV")

    # Criterion 4: Has length field with values (20 pts)
    if csv_analysis.get('has_length_field', False):
        score += 20
        subscores["has_length"] = True
        feedback_parts.append("Length field found")
    else:
        subscores["has_length"] = False
        feedback_parts.append("No length field found in CSV")

    # Criterion 5: Length values are positive and plausible (15 pts)
    # Sample roads span ~0.3 degrees. At this latitude, ~30-40 km range
    # In UTM meters, Road 1 is ~40km, Road 2 is ~33km
    # We accept any positive value between 1 and 500 km as plausible
    length_values = csv_analysis.get('length_values', [])
    if csv_analysis.get('lengths_valid', False) and length_values:
        all_plausible = all(0.1 <= v <= 500 for v in length_values)
        if all_plausible:
            score += 15
            subscores["lengths_plausible"] = True
            feedback_parts.append(f"Length values plausible: {[round(v, 2) for v in length_values]}")
        else:
            score += 5
            subscores["lengths_plausible"] = False
            feedback_parts.append(f"Some length values out of range: {length_values}")
    else:
        subscores["lengths_plausible"] = False
        feedback_parts.append("Length values invalid or missing")

    # Criterion 6: Both road names present (10 pts)
    has_road1 = csv_analysis.get('has_road1', False)
    has_road2 = csv_analysis.get('has_road2', False)
    if has_road1 and has_road2:
        score += 10
        subscores["both_roads"] = True
        feedback_parts.append("Both roads present (Road 1, Road 2)")
    elif has_road1 or has_road2:
        score += 5
        subscores["both_roads"] = False
        feedback_parts.append("Only one road found")
    else:
        subscores["both_roads"] = False
        feedback_parts.append("Road names not found")

    # Criterion 7: Reprojected GeoJSON exists (15 pts)
    if result.get('geojson_exists', False):
        geojson_size = result.get('geojson_size_bytes', 0)
        if geojson_size > 100:
            score += 15
            subscores["geojson_reprojected"] = True
            feedback_parts.append(f"Reprojected GeoJSON created ({geojson_size} bytes)")
        else:
            score += 5
            subscores["geojson_reprojected"] = False
            feedback_parts.append("Reprojected GeoJSON too small")
    else:
        subscores["geojson_reprojected"] = False
        feedback_parts.append("Reprojected GeoJSON not found")

    passed = score >= 55 and subscores.get("csv_exists", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
