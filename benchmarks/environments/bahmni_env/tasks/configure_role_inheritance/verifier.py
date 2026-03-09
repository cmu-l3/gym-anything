#!/usr/bin/env python3
"""
Verifier for configure_role_inheritance task.
Checks if the 'Trainee' role inherits from 'Provider'.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_role_inheritance(traj, env_info, task_info):
    """
    Verify that the 'Trainee' role inherits from 'Provider'.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check if role exists (20 pts)
    if result.get('role_exists', False):
        score += 20
        feedback_parts.append("Role 'Trainee' exists")
    else:
        return {"passed": False, "score": 0, "feedback": "Role 'Trainee' not found"}

    # 2. Check inheritance (60 pts)
    if result.get('inherits_provider', False):
        score += 60
        feedback_parts.append("Correctly inherits from 'Provider'")
    else:
        feedback_parts.append("Does NOT inherit from 'Provider'")

    # 3. Check for manual privileges (20 pts)
    # The goal is inheritance. If they manually added privileges, it's inefficient but partially functional.
    # However, the task specifically asked to configure inheritance.
    # We award points if they used inheritance and DIDN'T just dump privileges manually.
    priv_count = result.get('direct_privilege_count', 0)
    if priv_count == 0:
        score += 20
        feedback_parts.append("Clean configuration (no direct privileges)")
    else:
        # If they have privileges but ALSO inheritance, full points. 
        # If they have privileges but NO inheritance, they failed the main goal.
        # This criterion is "bonus" for doing it cleanly.
        feedback_parts.append(f"Role has {priv_count} direct privileges (should rely on inheritance)")

    passed = score >= 80  # Must exist (20) + inherit (60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }