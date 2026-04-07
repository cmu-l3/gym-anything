#!/usr/bin/env python3
"""
Verifier for fix_classroom_autograder task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_classroom_autograder(traj, env_info, task_info):
    """
    Score the autograder fix task.
    
    Criteria:
    1. All tests must pass (required for full score).
    2. Specific bug fixes verified via static analysis or specific test passes.
    3. Anti-gaming check on test files.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result file
    result_path = "/tmp/task_result.json"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Base scoring
    score = 0
    feedback_parts = []
    
    # 1. Check Anti-Gaming
    if result.get('tests_modified', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAIL: Test files were modified. You must fix the code, not the tests."
        }

    # 2. Score based on Tests Passing (Primary Signal)
    tests_passed = result.get('tests_passed', 0)
    total_tests = 10  # We created 10 tests/assertions roughly
    
    # Points for passing tests (up to 50 points)
    # We assign points based on specific bugs likely being fixed if tests pass
    
    # Bug 1: Late Penalty
    # Corresponds to test_late_penalty_three_days
    # If all tests passed, this passed. If specific static analysis confirms, good.
    bug1_fixed = result.get('bug1_static_fix', False)
    if bug1_fixed:
        score += 25
        feedback_parts.append("Bug 1 (Late Penalty) fixed")
    elif tests_passed > 0 and result.get('all_tests_pass', False):
        score += 25 # Trust the tests if static analysis was ambiguous but tests pass
        feedback_parts.append("Bug 1 (Late Penalty) fixed (verified by tests)")
    else:
        feedback_parts.append("Bug 1 (Late Penalty) NOT fixed")

    # Bug 2: Grade Boundaries
    # Corresponds to test_grade_boundary_exact_90
    bug2_fixed = result.get('bug2_static_fix', False)
    if bug2_fixed:
        score += 25
        feedback_parts.append("Bug 2 (Grade Boundaries) fixed")
    elif result.get('all_tests_pass', False):
        score += 25
        feedback_parts.append("Bug 2 (Grade Boundaries) fixed (verified by tests)")
    else:
        feedback_parts.append("Bug 2 (Grade Boundaries) NOT fixed")

    # Bug 3: Weighted Average
    # Corresponds to test_weighted_average_missing_category
    bug3_fixed = result.get('bug3_static_fix', False)
    if bug3_fixed:
        score += 25
        feedback_parts.append("Bug 3 (Weighted Average) fixed")
    elif result.get('all_tests_pass', False):
        score += 25
        feedback_parts.append("Bug 3 (Weighted Average) fixed (verified by tests)")
    else:
        feedback_parts.append("Bug 3 (Weighted Average) NOT fixed")
        
    # Bug 4: CSV Export
    # Corresponds to test_csv_column_order
    bug4_fixed = result.get('bug4_static_fix', False)
    if bug4_fixed:
        score += 25
        feedback_parts.append("Bug 4 (CSV Columns) fixed")
    elif result.get('all_tests_pass', False):
        score += 25
        feedback_parts.append("Bug 4 (CSV Columns) fixed (verified by tests)")
    else:
        feedback_parts.append("Bug 4 (CSV Columns) NOT fixed")

    # Regression penalty
    if not result.get('all_tests_pass', False) and score > 0:
        score = max(0, score - 20)
        feedback_parts.append("Penalty: Not all tests passed (possible regressions)")

    passed = score >= 60 and result.get('all_tests_pass', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }