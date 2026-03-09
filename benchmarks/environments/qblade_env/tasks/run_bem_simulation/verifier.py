#!/usr/bin/env python3
"""Verifier for run_bem_simulation task."""

import json
import tempfile
import os


def verify_run_bem_simulation(traj, env_info, task_info):
    """Verify that a BEM simulation was run and results exported."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # Criterion 1: Results file exists (25 pts)
    if result.get('results_file_exists'):
        score += 25
        feedback_parts.append("BEM results file created")
    else:
        feedback_parts.append("BEM results file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: File has multi-column numeric simulation data (25 pts)
    if result.get('has_numeric_data'):
        score += 25
        feedback_parts.append("File contains multi-column numeric data")
    else:
        feedback_parts.append("File does not contain valid multi-column numeric data")

    # Criterion 3: Sufficient data points (25 pts)
    data_points = result.get('data_points', 0)
    if data_points >= 10:
        score += 25
        feedback_parts.append(f"Sufficient data points ({data_points})")
    elif data_points >= 5:
        score += 12
        feedback_parts.append(f"Some data points ({data_points}, expected 10+)")
    else:
        feedback_parts.append(f"Too few data points ({data_points})")

    # Criterion 4: Has Cp and TSR labeled data (25 pts)
    if result.get('has_cp_data') and result.get('has_tsr_data'):
        score += 25
        feedback_parts.append("Cp and TSR data labeled correctly")
    elif result.get('has_cp_data') or result.get('has_tsr_data'):
        score += 12
        feedback_parts.append("Partial labeling of Cp/TSR columns")
    else:
        feedback_parts.append("Missing Cp/TSR labels in data")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
