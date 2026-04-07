#!/usr/bin/env python3
"""Verifier for go_on_duty_fire task."""

import json
import tempfile
import os


def verify_go_on_duty_fire(traj, env_info, task_info):
    """
    Verify that the agent logged in and went on duty as a Fire unit.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_dept_id = str(metadata.get('expected_dept_id', '6'))
    expected_status = metadata.get('expected_status', '10-8')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/go_on_duty_fire_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Check 1: Unit record exists (40 pts)
    # This implies they successfully logged in and accessed the patrol dashboard
    if result.get('unit_found'):
        score += 40
        feedback_parts.append("Active unit record found")
    else:
        feedback_parts.append("No active unit record found (did you click 10-8?)")
        return {"passed": False, "score": 0, "feedback": ". ".join(feedback_parts)}

    unit = result.get('unit', {})

    # Check 2: Correct Department (30 pts)
    # Should be Fire (ID 6)
    dept_id = str(unit.get('department_id', '')).strip()
    dept_name = str(unit.get('department_name', '')).strip()
    
    # Accept if ID matches OR if name contains "Fire"
    if dept_id == expected_dept_id or "fire" in dept_name.lower():
        score += 30
        feedback_parts.append(f"Correct department ({dept_name})")
    else:
        feedback_parts.append(f"Wrong department: {dept_name} (ID: {dept_id})")

    # Check 3: Correct Status (30 pts)
    status = str(unit.get('status', '')).strip()
    if status == expected_status:
        score += 30
        feedback_parts.append(f"Correct status: {status}")
    else:
        feedback_parts.append(f"Wrong status: {status} (expected {expected_status})")

    passed = score >= 100
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }