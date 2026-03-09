#!/usr/bin/env python3
"""
Verifier for create_new_project task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_new_project(traj, env_info, task_info):
    """
    Verify that a new QGIS project was created and saved.

    Checks:
    1. Project file exists at expected location or somewhere in projects dir
    2. Project file is valid (proper QGS XML or QGZ zip)
    3. Project file has reasonable size (> 0 bytes)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_project_name = metadata.get('expected_project_name', 'my_first_project.qgs')
    expected_project_dir = metadata.get('expected_project_dir', '/home/ga/GIS_Data/projects')

    criteria_met = 0
    total_criteria = 3
    feedback_parts = []

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    logger.info(f"Task result: {result}")

    # Criterion 1: Check if expected project file was found
    expected_found = result.get('expected_found', False)
    project_path = result.get('project_path', '')

    if expected_found:
        criteria_met += 1
        feedback_parts.append(f"Project saved at expected location")
    elif project_path:
        # Partial credit if project was saved but not at expected location
        criteria_met += 0.5
        project_name = os.path.basename(project_path)
        feedback_parts.append(f"Project saved as '{project_name}' (expected '{expected_project_name}')")
    else:
        feedback_parts.append("No project file found")

    # Criterion 2: Check if project file is valid
    project_valid = result.get('project_valid', False)
    if project_valid:
        criteria_met += 1
        feedback_parts.append("Project file is valid")
    else:
        if project_path:
            feedback_parts.append("Project file may be invalid or corrupted")
        else:
            feedback_parts.append("Cannot validate - no project file")

    # Criterion 3: Check file size (should be > 0)
    project_size = result.get('project_size_bytes', 0)
    if project_size > 100:  # A valid QGIS project should be at least 100 bytes
        criteria_met += 1
        feedback_parts.append(f"Project size: {project_size} bytes")
    elif project_size > 0:
        criteria_met += 0.5
        feedback_parts.append(f"Project size is small: {project_size} bytes")
    else:
        feedback_parts.append("Project file is empty or missing")

    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 65 and bool(project_path)  # Need at least 65% and some project file

    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
