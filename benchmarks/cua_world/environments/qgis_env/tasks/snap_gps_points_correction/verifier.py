#!/usr/bin/env python3
"""Verifier for snap_gps_points_correction task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_snap_gps_points_correction(traj, env_info, task_info):
    """
    Verify that points were snapped to the road network.

    Scoring (100 points):
    - Output file exists and created during task: 20 points
    - Valid GeoJSON structure: 10 points
    - Feature count matches input (6 points): 20 points
    - Points are snapped to lines (dist < 1e-6): 30 points
    - Points moved from original positions: 20 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_count = metadata.get('expected_count', 6)
    max_allowed_dist = metadata.get('max_allowed_distance_deg', 1e-6)

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

    # Criterion 1: File existence and freshness (20 pts)
    if result.get('file_exists', False):
        if result.get('file_created_during_task', False):
            score += 20
            subscores["file_fresh"] = True
            feedback_parts.append("New output file created")
        else:
            score += 10
            subscores["file_fresh"] = False
            feedback_parts.append("Output file exists but was not modified during task")
    else:
        feedback_parts.append("Output file not found")
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # Criterion 2: Valid GeoJSON (10 pts)
    if analysis.get('valid_json', False):
        score += 10
        subscores["valid_json"] = True
    else:
        feedback_parts.append("Invalid GeoJSON or analysis failed")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 3: Feature Count (20 pts)
    count = analysis.get('feature_count', 0)
    if count == expected_count:
        score += 20
        subscores["count_match"] = True
        feedback_parts.append(f"Correct feature count ({count})")
    else:
        # Partial credit if some features exist
        if count > 0:
            score += 5
        subscores["count_match"] = False
        feedback_parts.append(f"Feature count mismatch: got {count}, expected {expected_count}")

    # Criterion 4: Snapping Accuracy (30 pts)
    # We check if max distance to line is effectively zero
    max_dist = analysis.get('max_distance_to_line', 1.0)
    if max_dist < max_allowed_dist:
        score += 30
        subscores["snapped"] = True
        feedback_parts.append("Points successfully snapped to lines")
    elif max_dist < 0.001: # 0.001 deg is ~100m, still too far for "snapped" but closer than random
        score += 5
        subscores["snapped"] = False
        feedback_parts.append(f"Points close but not snapped (max dist: {max_dist:.6f})")
    else:
        subscores["snapped"] = False
        feedback_parts.append(f"Points not snapped (max dist: {max_dist:.6f})")

    # Criterion 5: Modification Check (20 pts)
    if analysis.get('movement_detected', False):
        score += 20
        subscores["moved"] = True
        feedback_parts.append("Points were moved from original locations")
    else:
        subscores["moved"] = False
        feedback_parts.append("Points identical to input (no processing applied)")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }