#!/usr/bin/env python3
"""Verifier for design_hawt_blade task."""

import json
import tempfile
import os


def verify_design_hawt_blade(traj, env_info, task_info):
    """Verify that a HAWT blade was designed and project saved."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})

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

    # Criterion 1: Project file exists (30 pts)
    if result.get('project_file_exists'):
        score += 30
        feedback_parts.append("Project file hawt_blade.wpa saved")
    else:
        feedback_parts.append("Project file hawt_blade.wpa not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: File is not a simple copy of a sample project (25 pts)
    if result.get('file_is_unique', False):
        score += 25
        feedback_parts.append("Project file is agent-modified (not a copy)")
    else:
        feedback_parts.append("Project file appears to be an unmodified copy of a sample project")

    # Criterion 3: File has substantial content (25 pts)
    project_size = result.get('project_file_size', 0)
    if project_size > 10000:
        score += 25
        feedback_parts.append(f"Project file has substantial content ({project_size} bytes)")
    elif project_size > 1000:
        score += 15
        feedback_parts.append(f"Project file is small ({project_size} bytes)")
    else:
        feedback_parts.append(f"Project file is too small ({project_size} bytes)")

    # Criterion 4: QBlade was used (20 pts)
    if result.get('qblade_running'):
        score += 20
        feedback_parts.append("QBlade is running")
    else:
        feedback_parts.append("QBlade is not running")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
