#!/usr/bin/env python3
"""Verifier for load_sample_project task."""

import json
import tempfile
import os


def verify_load_sample_project(traj, env_info, task_info):
    """Verify that a sample project was loaded and saved as my_turbine.wpa."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})

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

    feedback_parts = []
    score = 0

    # Criterion 1: my_turbine.wpa exists at the expected path (50 pts)
    if result.get('project_file_exists'):
        score += 50
        feedback_parts.append("Project file my_turbine.wpa saved successfully")
    else:
        feedback_parts.append("my_turbine.wpa not found at expected path")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Project file has substantial content (30 pts)
    project_size = result.get('project_file_size', 0)
    if project_size > 1000:
        score += 30
        feedback_parts.append(f"Project file has substantial content ({project_size} bytes)")
    elif project_size > 100:
        score += 15
        feedback_parts.append(f"Project file is small ({project_size} bytes, expected >1KB for a real project)")
    else:
        feedback_parts.append(f"Project file is too small ({project_size} bytes)")

    # Criterion 3: File is not a simple copy of a pre-existing sample (20 pts)
    if result.get('file_is_unique', False):
        score += 20
        feedback_parts.append("Project file appears to be agent-created")
    elif project_size > 1000:
        score += 10
        feedback_parts.append("Project file exists but could not confirm it was agent-created")
    else:
        feedback_parts.append("Project file may not have been created by QBlade")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
