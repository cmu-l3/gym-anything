#!/usr/bin/env python3
"""Verifier for create_project task."""

import json
import tempfile
import os


def verify_create_project(traj, env_info, task_info):
    """Verify that a new project was created with the expected name."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_project_name', 'Protein Crystallization Study')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_project_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    criteria_passed = 0
    total_criteria = 3
    feedback_parts = []

    initial_count = int(result.get('initial_project_count', 0))
    current_count = int(result.get('current_project_count', 0))
    project_found = result.get('project_found', False)
    project = result.get('project', {})

    # Criterion 1: Project with expected name exists
    if project_found:
        actual_name = project.get('name', '')
        if actual_name.strip().lower() == expected_name.strip().lower():
            criteria_passed += 1
            feedback_parts.append(f"Project '{expected_name}' found")
        else:
            feedback_parts.append(f"Name mismatch: expected '{expected_name}', got '{actual_name}'")
    else:
        feedback_parts.append(f"Project '{expected_name}' not found in database")

    # Criterion 2: Project count increased
    if current_count > initial_count:
        criteria_passed += 1
        feedback_parts.append(f"Project count increased ({initial_count} -> {current_count})")
    else:
        feedback_parts.append(f"Project count unchanged ({initial_count} -> {current_count})")

    # Criterion 3: Project has a valid ID (was actually created in DB)
    project_id = project.get('id', '')
    if project_id and project_id.strip():
        criteria_passed += 1
        feedback_parts.append(f"Project has valid ID: {project_id}")
    else:
        # Check partial match or newest project
        partial = result.get('partial_match', '')
        newest = result.get('newest_project', '')
        if partial:
            feedback_parts.append(f"Partial match found: {partial}")
        elif newest:
            feedback_parts.append(f"Newest project: {newest}")
        else:
            feedback_parts.append("No project ID found")

    score = int((criteria_passed / total_criteria) * 100)
    passed = score >= 67  # Pass if >= 2/3 criteria met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "name_match": project_found and project.get('name', '').strip().lower() == expected_name.strip().lower(),
            "count_increased": current_count > initial_count,
            "valid_id": bool(project_id and project_id.strip())
        }
    }
