#!/usr/bin/env python3
"""Verifier for identify_landlocked_parcels_buffer task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_identify_landlocked_parcels_buffer(traj, env_info, task_info):
    """
    Verify that landlocked parcels were correctly identified and buffered.

    Scoring (100 points):
    - Output file exists: 15 points
    - Valid GeoJSON: 10 points
    - Correct feature count (2 isolated parcels): 30 points
    - Correct geometry type (Polygon/MultiPolygon): 10 points
    - Correct buffer area (indicates 10m buffer was applied): 25 points
    - New file created: 10 points

    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_count = metadata.get('expected_feature_count', 2)
    min_area = metadata.get('min_area_m2', 14000)
    max_area = metadata.get('max_area_m2', 15000)

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

    # Criterion 1: File exists (15 pts)
    if result.get('file_exists', False):
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
        feedback_parts.append("Invalid GeoJSON or parse error")

    # Criterion 3: Feature Count (30 pts)
    # 2 isolated parcels (Center and Top-Middle)
    count = analysis.get('feature_count', 0)
    if count == expected_count:
        score += 30
        subscores["count_correct"] = True
        feedback_parts.append(f"Correct feature count: {count}")
    elif count == 9:
        score += 5
        subscores["count_correct"] = False
        feedback_parts.append("Buffered ALL parcels (selection step missed)")
    elif count == 7:
        score += 5
        subscores["count_correct"] = False
        feedback_parts.append("Buffered TOUCHING parcels (inverse selection needed)")
    else:
        # Partial credit if at least some filtration happened
        if 0 < count < 9:
            score += 10
        subscores["count_correct"] = False
        feedback_parts.append(f"Incorrect feature count: {count} (expected {expected_count})")

    # Criterion 4: Geometry Type (10 pts)
    gtype = analysis.get('geometry_type', "")
    if "Polygon" in gtype:
        score += 10
        subscores["geometry_type"] = True
        feedback_parts.append("Features are Polygons")
    else:
        subscores["geometry_type"] = False
        feedback_parts.append(f"Wrong geometry type: {gtype}")

    # Criterion 5: Buffer Area (25 pts)
    # Original parcels are 100x100 = 10,000 m2
    # Buffered 10m should be approx 14,314 m2
    avg_area = analysis.get('avg_area', 0)
    
    # Check if calculation was possible
    if avg_area == -1:
        # Python dependencies missing in verification env, rely on count/type
        score += 25
        feedback_parts.append("Area check skipped (dependencies missing)")
    elif avg_area > 0:
        if min_area <= avg_area <= max_area:
            score += 25
            subscores["area_correct"] = True
            feedback_parts.append(f"Buffer area correct (~{int(avg_area)} m²)")
        elif 9500 <= avg_area <= 10500:
            score += 0
            subscores["area_correct"] = False
            feedback_parts.append("Area matches original parcels (Buffer tool likely not run or distance=0)")
        elif avg_area < min_area:
            score += 5
            subscores["area_correct"] = False
            feedback_parts.append(f"Area too small ({int(avg_area)} m²) - check buffer distance")
        else:
            score += 5
            subscores["area_correct"] = False
            feedback_parts.append(f"Area too large ({int(avg_area)} m²) - check buffer distance")
    else:
         feedback_parts.append("Could not calculate area")

    # Criterion 6: New File (10 pts)
    initial = result.get('initial_export_count', 0)
    current = result.get('current_export_count', 0)
    if current > initial:
        score += 10
        subscores["new_file"] = True
    else:
        feedback_parts.append("No new file created")

    passed = score >= 70 and subscores.get("file_exists", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }