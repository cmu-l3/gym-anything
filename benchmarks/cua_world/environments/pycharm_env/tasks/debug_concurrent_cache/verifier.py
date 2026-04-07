#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_debug_concurrent_cache(traj, env_info, task_info):
    """
    Verify the debug_concurrent_cache task.
    
    Scoring:
    - 25 pts per fixed bug (verified by specific test passing).
    - 0 pts if test files were modified.
    - 0 pts if source code was not touched (magic pass?).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/debug_concurrent_cache_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 1. Check Constraints
    if result.get("tests_modified", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAIL: Test files were modified. You must fix the code, not the tests.",
            "details": {"tests_modified": True}
        }

    if not result.get("source_files_modified", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAIL: Source files were not modified. No fix attempt detected.",
            "details": {"source_files_modified": False}
        }

    # 2. Calculate Score
    score = 0
    feedback_parts = []
    
    # Bug 1: Eviction Race
    if result.get("pass_bug1_eviction", False):
        score += 25
        feedback_parts.append("Bug 1 (Eviction Race) fixed")
    else:
        feedback_parts.append("Bug 1 (Eviction Race) NOT fixed")

    # Bug 2: Deadlock
    if result.get("pass_bug2_deadlock", False):
        score += 25
        feedback_parts.append("Bug 2 (Deadlock) fixed")
    else:
        feedback_parts.append("Bug 2 (Deadlock) NOT fixed")

    # Bug 3: Stats Race
    if result.get("pass_bug3_stats", False):
        score += 25
        feedback_parts.append("Bug 3 (Stats Accuracy) fixed")
    else:
        feedback_parts.append("Bug 3 (Stats Accuracy) NOT fixed")

    # Bug 4: TOCTOU
    if result.get("pass_bug4_toctou", False):
        score += 25
        feedback_parts.append("Bug 4 (TTL Race) fixed")
    else:
        feedback_parts.append("Bug 4 (TTL Race) NOT fixed")

    # 3. Final Verification
    passed = (score == 100)
    
    # Bonus check: Did ALL tests pass?
    total_passed = result.get("tests_passed", 0)
    total_tests = result.get("tests_total", 0)
    
    if total_passed < total_tests and passed:
        # If specific bugs passed but regressions occurred elsewhere
        passed = False
        feedback_parts.append(f"Regressions detected: only {total_passed}/{total_tests} tests passed")
        score = max(0, score - 10) # Penalty for breaking other things

    return {
        "passed": passed,
        "score": score,
        "feedback": ", ".join(feedback_parts),
        "details": result
    }