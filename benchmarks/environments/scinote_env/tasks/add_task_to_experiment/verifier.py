#!/usr/bin/env python3
"""Verifier for add_task_to_experiment task."""

import json
import tempfile
import os


def verify_add_task_to_experiment(traj, env_info, task_info):
    """Verify that a new task (my_module) was added to the expected experiment."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_task_name', 'Run Mass Spec Calibration')
    expected_experiment = metadata.get('expected_experiment_name', 'LC-MS Compound Screening')
    expected_project = metadata.get('expected_project_name', 'Drug Discovery Pipeline')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/add_task_result.json", temp_file.name)
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

    initial_count = int(result.get('initial_task_count', 0))
    current_count = int(result.get('current_task_count', 0))
    task_found = result.get('task_found', False)
    task = result.get('task', {})

    # Criterion 1: Task with expected name exists
    if task_found:
        actual_name = task.get('name', '')
        if actual_name.strip().lower() == expected_name.strip().lower():
            criteria_passed += 1
            feedback_parts.append(f"Task '{expected_name}' found")
        else:
            feedback_parts.append(f"Name mismatch: expected '{expected_name}', got '{actual_name}'")
    else:
        feedback_parts.append(f"Task '{expected_name}' not found")

    # Criterion 2: Task is in the correct experiment
    if task_found:
        experiment_name = task.get('experiment_name', '')
        if experiment_name.strip().lower() == expected_experiment.strip().lower():
            criteria_passed += 1
            feedback_parts.append(f"Correct experiment: '{expected_experiment}'")
        else:
            feedback_parts.append(f"Wrong experiment: expected '{expected_experiment}', got '{experiment_name}'")
    else:
        feedback_parts.append("Cannot check experiment (task not found)")

    # Criterion 3: Task count increased
    if current_count > initial_count:
        criteria_passed += 1
        feedback_parts.append(f"Task count increased ({initial_count} -> {current_count})")
    else:
        feedback_parts.append(f"Task count unchanged ({initial_count} -> {current_count})")

    # Criterion 4: Task is in the correct project
    if task_found:
        project_name = task.get('project_name', '')
        if project_name.strip().lower() == expected_project.strip().lower():
            criteria_passed += 1
            feedback_parts.append(f"Correct project: '{expected_project}'")
        else:
            feedback_parts.append(f"Wrong project: expected '{expected_project}', got '{project_name}'")
    else:
        feedback_parts.append("Cannot check project (task not found)")

    score = int((criteria_passed / total_criteria) * 100)
    passed = score >= 75  # Pass if >= 3/4 criteria

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "name_match": task_found and task.get('name', '').strip().lower() == expected_name.strip().lower(),
            "correct_experiment": task_found and task.get('experiment_name', '').strip().lower() == expected_experiment.strip().lower(),
            "count_increased": current_count > initial_count,
            "correct_project": task_found and task.get('project_name', '').strip().lower() == expected_project.strip().lower()
        }
    }
