#!/usr/bin/env python3
"""Verifier for import_airfoil_dat task."""

import json
import tempfile
import os


def verify_import_airfoil_dat(traj, env_info, task_info):
    """Verify that airfoil was imported and XFoil polar analysis was exported."""

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

    # Criterion 1: Airfoil was imported into QBlade (20 pts)
    if result.get('airfoil_imported'):
        score += 20
        feedback_parts.append("Airfoil successfully imported into QBlade")
    else:
        feedback_parts.append("Airfoil import not confirmed")

    # Criterion 2: Polar file exists (25 pts)
    if result.get('polar_file_exists'):
        score += 25
        feedback_parts.append("Polar analysis file created")
    else:
        feedback_parts.append("Polar analysis file not found")
        if score == 0:
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        else:
            passed = score >= 70
            return {"passed": passed, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 3: Polar file has aerodynamic data columns (30 pts)
    if result.get('has_polar_data'):
        score += 30
        feedback_parts.append(f"Polar file contains aerodynamic data ({result.get('polar_lines', 0)} lines)")
    else:
        feedback_parts.append("Polar file does not contain valid aerodynamic data")

    # Criterion 4: Sufficient data points covering AoA range (25 pts)
    polar_lines = result.get('polar_lines', 0)
    has_negative_aoa = result.get('has_negative_aoa', False)
    if polar_lines >= 10 and has_negative_aoa:
        score += 25
        feedback_parts.append(f"Good AoA coverage with negative angles ({polar_lines} data points)")
    elif polar_lines >= 10:
        score += 15
        feedback_parts.append(f"Sufficient data points ({polar_lines}) but missing negative AoA range")
    elif polar_lines >= 5:
        score += 10
        feedback_parts.append(f"Some polar data ({polar_lines} lines, expected 10+)")
    else:
        feedback_parts.append(f"Too few polar data points ({polar_lines} lines)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
