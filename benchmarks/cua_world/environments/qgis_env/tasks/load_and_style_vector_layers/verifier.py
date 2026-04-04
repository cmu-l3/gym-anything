#!/usr/bin/env python3
"""Verifier for load_and_style_vector_layers task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_load_and_style_vector_layers(traj, env_info, task_info):
    """
    Verify that vector layers were loaded and styled in a QGIS project.

    Scoring (100 points):
    - Project file exists at expected location: 20 points
    - Project is valid format: 10 points
    - Polygon layer loaded: 20 points
    - Point layer loaded: 20 points
    - Both layers present (2+ layers): 15 points
    - Project file has substantial size (styled content): 15 points

    Pass threshold: 65 points (must have project + both layers minimum)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})

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

    # Criterion 1: Project file exists at expected location (20 pts)
    project_found = result.get('project_found', False)
    if project_found:
        score += 20
        subscores["project_exists"] = True
        feedback_parts.append("Project file found at expected location")
    elif result.get('project_path'):
        score += 10
        subscores["project_exists"] = True
        feedback_parts.append(f"Project saved at different location: {result['project_path']}")
    else:
        subscores["project_exists"] = False
        feedback_parts.append("No project file found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Project is valid format (10 pts)
    if result.get('project_valid', False):
        score += 10
        subscores["valid_format"] = True
        feedback_parts.append("Project file is valid")
    else:
        subscores["valid_format"] = False
        feedback_parts.append("Project file may be invalid")

    # Criterion 3: Polygon layer loaded (20 pts)
    if result.get('has_polygon_layer', False):
        score += 20
        subscores["polygon_layer"] = True
        feedback_parts.append(f"Polygon layer loaded: {result.get('polygon_layer_name', 'found')}")
    else:
        subscores["polygon_layer"] = False
        feedback_parts.append("Polygon layer NOT found in project")

    # Criterion 4: Point layer loaded (20 pts)
    if result.get('has_point_layer', False):
        score += 20
        subscores["point_layer"] = True
        feedback_parts.append(f"Point layer loaded: {result.get('point_layer_name', 'found')}")
    else:
        subscores["point_layer"] = False
        feedback_parts.append("Point layer NOT found in project")

    # Criterion 5: Both layers present - at least 2 layers (15 pts)
    layer_count = result.get('layer_count', 0)
    if layer_count >= 2:
        score += 15
        subscores["multiple_layers"] = True
        feedback_parts.append(f"Project contains {layer_count} layers")
    else:
        subscores["multiple_layers"] = False
        feedback_parts.append(f"Only {layer_count} layer(s) found (expected 2+)")

    # Criterion 6: Project has substantial size indicating styling was saved (15 pts)
    project_size = result.get('project_size_bytes', 0)
    if project_size > 2000:
        score += 15
        subscores["substantial_size"] = True
        feedback_parts.append(f"Project size: {project_size} bytes (styled content)")
    elif project_size > 500:
        score += 7
        subscores["substantial_size"] = True
        feedback_parts.append(f"Project size: {project_size} bytes (minimal content)")
    else:
        subscores["substantial_size"] = False
        feedback_parts.append(f"Project size too small: {project_size} bytes")

    passed = score >= 65 and subscores.get("project_exists", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
