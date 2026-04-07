#!/usr/bin/env python3
"""Verifier for add_department task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_department(traj, env_info, task_info):
    """
    Verify that the 'Mine Safety Division' department was added.
    
    Criteria:
    1. Department exists in database (30 pts)
    2. Name matches 'Mine Safety Division' exactly (case-insensitive) (30 pts)
    3. Short name matches 'MSD' (20 pts)
    4. New record created (Count increased) (20 pts)
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'Mine Safety Division').lower()
    expected_short = metadata.get('expected_short_name', 'MSD').upper()

    # Retrieve result file
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

    score = 0
    feedback_parts = []
    
    dept = result.get('department', {})
    
    # Criterion 1: Department Found
    if result.get('dept_found'):
        score += 30
        feedback_parts.append("Department record found")
    else:
        feedback_parts.append("Department 'Mine Safety Division' NOT found in database")
        # Fail immediately if not found
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Name Exact Match
    actual_name = (dept.get('name') or '').strip()
    if actual_name.lower() == expected_name:
        score += 30
        feedback_parts.append(f"Name matches exactly: {actual_name}")
    else:
        # Partial match credit
        if expected_name in actual_name.lower():
            score += 15
            feedback_parts.append(f"Name partial match: '{actual_name}'")
        else:
            feedback_parts.append(f"Name mismatch: expected '{expected_name}', got '{actual_name}'")

    # Criterion 3: Short Name Match
    actual_short = (dept.get('short_name') or '').strip().upper()
    if actual_short == expected_short:
        score += 20
        feedback_parts.append(f"Short name matches: {actual_short}")
    elif actual_short:
        score += 5
        feedback_parts.append(f"Short name mismatch: expected '{expected_short}', got '{actual_short}'")
    else:
        feedback_parts.append("Short name is empty")

    # Criterion 4: Anti-Gaming / Freshness
    initial = result.get('initial_count', 0)
    current = result.get('current_count', 0)
    if current > initial:
        score += 20
        feedback_parts.append("New record creation confirmed")
    else:
        feedback_parts.append("No increase in department count detected")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }