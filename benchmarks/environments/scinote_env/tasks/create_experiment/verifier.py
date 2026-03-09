#!/usr/bin/env python3
"""Verifier for create_experiment task."""

import json
import tempfile
import os


def verify_create_experiment(traj, env_info, task_info):
    """Verify that a new experiment was created with the expected name in the expected project."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_experiment_name', 'HPLC Analysis Run 3')
    expected_project = metadata.get('expected_project_name', 'Drug Discovery Pipeline')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_experiment_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    criteria_passed = 0
    total_criteria = 4
    feedback_parts = []

    initial_count = int(result.get('initial_experiment_count', 0))
    current_count = int(result.get('current_experiment_count', 0))
    experiment_found = result.get('experiment_found', False)
    experiment = result.get('experiment', {})

    # Criterion 1: Experiment with expected name exists
    if experiment_found:
        actual_name = experiment.get('name', '')
        if actual_name.strip().lower() == expected_name.strip().lower():
            criteria_passed += 1
            feedback_parts.append(f"Experiment '{expected_name}' found")
        else:
            feedback_parts.append(f"Name mismatch: expected '{expected_name}', got '{actual_name}'")
    else:
        feedback_parts.append(f"Experiment '{expected_name}' not found")

    # Criterion 2: Experiment is in the correct project
    if experiment_found:
        project_name = experiment.get('project_name', '')
        if project_name.strip().lower() == expected_project.strip().lower():
            criteria_passed += 1
            feedback_parts.append(f"Correct project: '{expected_project}'")
        else:
            feedback_parts.append(f"Wrong project: expected '{expected_project}', got '{project_name}'")
    else:
        feedback_parts.append("Cannot check project (experiment not found)")

    # Criterion 3: Experiment count increased
    if current_count > initial_count:
        criteria_passed += 1
        feedback_parts.append(f"Experiment count increased ({initial_count} -> {current_count})")
    else:
        feedback_parts.append(f"Experiment count unchanged ({initial_count} -> {current_count})")

    # Criterion 4: Valid experiment ID
    experiment_id = experiment.get('id', '')
    if experiment_id and experiment_id.strip():
        criteria_passed += 1
        feedback_parts.append(f"Valid experiment ID: {experiment_id}")
    else:
        feedback_parts.append("No valid experiment ID")

    score = int((criteria_passed / total_criteria) * 100)
    passed = score >= 75  # Pass if >= 3/4 criteria

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "name_match": experiment_found and experiment.get('name', '').strip().lower() == expected_name.strip().lower(),
            "correct_project": experiment_found and experiment.get('project_name', '').strip().lower() == expected_project.strip().lower(),
            "count_increased": current_count > initial_count,
            "valid_id": bool(experiment_id and experiment_id.strip())
        }
    }
