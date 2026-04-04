#!/usr/bin/env python3
"""Verifier for repair_invalid_geometry_parcels task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_repair_invalid_geometry_parcels(traj, env_info, task_info):
    """
    Verify that invalid geometries were repaired.

    Scoring (100 points):
    - Output file exists: 20 points
    - File created/modified during task: 10 points
    - Valid GeoJSON: 10 points
    - All features have valid geometry (shapely.is_valid): 30 points
    - Feature count >= 3 (preserved features): 15 points
    - Attributes preserved (checked via owner='Doe'): 15 points

    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

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

    analysis = result.get('analysis', {})
    score = 0
    feedback_parts = []
    subscores = {}

    # Criterion 1: File Exists (20 pts)
    if analysis.get('file_exists', False):
        score += 20
        subscores['file_exists'] = True
        feedback_parts.append("Output file found")
    else:
        subscores['file_exists'] = False
        feedback_parts.append("Output file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Anti-gaming Timestamp (10 pts)
    if analysis.get('file_created_during_task', False):
        score += 10
        subscores['new_file'] = True
    else:
        subscores['new_file'] = False
        feedback_parts.append("File not created/modified during task")

    # Criterion 3: Valid GeoJSON (10 pts)
    if analysis.get('is_valid_json', False):
        score += 10
        subscores['valid_json'] = True
    else:
        subscores['valid_json'] = False
        feedback_parts.append("Invalid GeoJSON format")

    # Criterion 4: Geometry Validity (30 pts)
    # This is the core task - fixing the bowtie
    if analysis.get('all_geometries_valid', False):
        score += 30
        subscores['geom_valid'] = True
        feedback_parts.append("All geometries are valid")
    else:
        invalid_count = analysis.get('invalid_count', 0)
        subscores['geom_valid'] = False
        feedback_parts.append(f"Found {invalid_count} invalid geometries (failed to fix)")

    # Criterion 5: Feature Retention (15 pts)
    # Should have at least 3 features (original 3, or more if split)
    count = analysis.get('feature_count', 0)
    if count >= 3:
        score += 15
        subscores['retention'] = True
        feedback_parts.append(f"Feature count: {count}")
    else:
        subscores['retention'] = False
        feedback_parts.append(f"Feature count low: {count} (expected >= 3)")

    # Criterion 6: Attribute Preservation (15 pts)
    # Specifically check if the 'Doe' record survived
    if analysis.get('doe_owner_found', False) and analysis.get('attributes_preserved', False):
        score += 15
        subscores['attributes'] = True
        feedback_parts.append("Attributes preserved")
    else:
        subscores['attributes'] = False
        feedback_parts.append("Attributes missing or corrupted")

    # Pass if file exists, valid geometries, and attributes preserved
    passed = score >= 70 and subscores.get('geom_valid', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }