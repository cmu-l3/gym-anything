#!/usr/bin/env python3
"""
Verifier for fix_rigid_body_physics task.
Checks if the 3 critical bugs in the physics engine were fixed.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_rigid_body_physics(traj, env_info, task_info):
    """
    Verify physics engine fixes.
    
    Scoring:
    - Bug 1 (Integration): 30 pts
    - Bug 2 (Impulse): 30 pts
    - Bug 3 (Correction): 30 pts
    - All tests pass (No regression): 10 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/fix_physics_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Bug 1: Integration (dt)
    if result.get("bug1_fixed"):
        score += 30
        feedback_parts.append("Integration bug fixed (dt applied)")
    else:
        feedback_parts.append("Integration bug NOT fixed (dt missing)")

    # Bug 2: Impulse (mass)
    if result.get("bug2_fixed"):
        score += 30
        feedback_parts.append("Impulse bug fixed (inverse mass used)")
    else:
        feedback_parts.append("Impulse bug NOT fixed (wrong mass denominator)")

    # Bug 3: Correction (signs)
    if result.get("bug3_fixed"):
        score += 30
        feedback_parts.append("Positional correction bug fixed (signs corrected)")
    else:
        feedback_parts.append("Positional correction bug NOT fixed (objects still pull together)")

    # No Regression
    if result.get("all_tests_pass"):
        score += 10
        feedback_parts.append("All tests pass (No regressions)")
    else:
        feedback_parts.append(f"Some tests failing ({result.get('tests_failed')} failures)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ", ".join(feedback_parts)
    }