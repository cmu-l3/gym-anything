#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_key_value_store(traj, env_info, task_info):
    """
    Verify the fix_key_value_store task.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    task_name = "fix_key_value_store"
    result_path = f"/tmp/{task_name}_result.json"
    
    # Retrieve result file
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        copy_from_env(result_path, tmp_path)
        with open(tmp_path, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    score = 0
    feedback = []

    # 1. Test Suite Pass Rate (Max 10 pts)
    # Just running the tests and keeping regressions away
    passed_tests = result.get("tests_passed", 0)
    total_tests = result.get("total_tests", 0)
    
    if total_tests > 0:
        if passed_tests == total_tests:
            score += 10
            feedback.append("All tests passed (+10)")
        else:
            feedback.append(f"Tests passing: {passed_tests}/{total_tests}")

    # 2. Bug 1: Binary Search Fix (30 pts)
    if result.get("bug1_binary_search_fixed", False):
        score += 30
        feedback.append("Binary search boundary bug fixed (+30)")
    else:
        feedback.append("Binary search bug NOT fixed")

    # 3. Bug 2: Merge Priority Fix (30 pts)
    if result.get("bug2_merge_priority_fixed", False):
        score += 30
        feedback.append("Merge priority inversion bug fixed (+30)")
    else:
        feedback.append("Merge priority bug NOT fixed")

    # 4. Bug 3: Tombstone Fix (30 pts)
    if result.get("bug3_tombstone_fixed", False):
        score += 30
        feedback.append("Tombstone handling bug fixed (+30)")
    else:
        feedback.append("Tombstone bug NOT fixed")

    # Calculate final status
    is_passed = score >= 70
    
    return {
        "passed": is_passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }