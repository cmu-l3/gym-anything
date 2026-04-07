#!/usr/bin/env python3
"""Verifier for grant_joint_access task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_grant_joint_access(traj, env_info, task_info):
    """
    Verify that the Dispatch Officer was granted access to Sheriff and Highway departments.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/grant_joint_access_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    dept_ids = result.get('department_ids', [])
    current_count = result.get('current_dept_count', 0)
    initial_count = result.get('initial_dept_count', 0)
    
    # Criterion 1: Sheriff Access (ID 4) - 30 pts
    if result.get('has_sheriff', False):
        score += 30
        feedback_parts.append("Sheriff access granted")
    else:
        feedback_parts.append("Missing Sheriff access")

    # Criterion 2: Highway Access (ID 3) - 30 pts
    if result.get('has_highway', False):
        score += 30
        feedback_parts.append("Highway access granted")
    else:
        feedback_parts.append("Missing Highway access")

    # Criterion 3: Communications Retained (ID 1) - 20 pts
    if result.get('has_communications', False):
        score += 20
        feedback_parts.append("Communications access retained")
    else:
        feedback_parts.append("Communications access was REMOVED (should be retained)")

    # Criterion 4: Exact Count Integrity (10 pts)
    # Should have exactly 3 departments. If they added Fire/EMS randomly, penalize.
    if current_count == 3:
        score += 10
        feedback_parts.append("Correct number of departments (3)")
    else:
        feedback_parts.append(f"Incorrect department count: {current_count} (expected 3)")

    # Criterion 5: Anti-gaming / Action verification (10 pts)
    # Check that state actually changed from initial
    if current_count > initial_count:
        score += 10
        feedback_parts.append("Database state modified successfully")
    elif current_count == initial_count:
        # If count didn't change, they probably didn't do anything (unless they started with correct state, which setup prevents)
        feedback_parts.append("No changes detected in department count")
    
    # Pass threshold
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }