#!/usr/bin/env python3
"""Verifier for generate_naca_airfoil task."""

import json
import tempfile
import os


def verify_generate_naca_airfoil(traj, env_info, task_info):
    """Verify that a NACA 4412 airfoil was generated and exported."""

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

    # Criterion 1: Generated file exists (25 pts)
    if result.get('file_exists'):
        score += 25
        feedback_parts.append("Generated airfoil file created")
    else:
        feedback_parts.append("Generated airfoil file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: File has coordinate data (25 pts)
    if result.get('has_coordinates'):
        score += 25
        feedback_parts.append(f"File contains coordinate data ({result.get('file_lines', 0)} lines)")
    else:
        feedback_parts.append("File does not contain valid coordinate data")

    # Criterion 3: File header contains "4412" (NACA 4412 specifically) (25 pts)
    if result.get('header_has_4412'):
        score += 25
        feedback_parts.append("File header identifies NACA 4412 airfoil")
    elif result.get('looks_like_naca'):
        score += 10
        feedback_parts.append("File mentions NACA but not specifically 4412")
    else:
        feedback_parts.append("File does not identify as NACA 4412")

    # Criterion 4: Sufficient coordinate points and not a copy (25 pts)
    file_lines = result.get('file_lines', 0)
    is_copy = result.get('is_copy_of_existing', False)
    if is_copy:
        feedback_parts.append(f"File appears to be a copy of the pre-existing airfoil data ({file_lines} lines)")
    elif file_lines >= 50:
        score += 25
        feedback_parts.append(f"Sufficient coordinate points ({file_lines} lines)")
    elif file_lines >= 20:
        score += 15
        feedback_parts.append(f"Some coordinate points ({file_lines} lines, expected 50+)")
    else:
        feedback_parts.append(f"Too few coordinate points ({file_lines} lines)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
