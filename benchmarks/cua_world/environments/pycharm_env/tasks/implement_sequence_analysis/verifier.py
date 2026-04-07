#!/usr/bin/env python3
"""
Verifier for implement_sequence_analysis task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_sequence_analysis(traj, env_info, task_info):
    """
    Verify the bioinformatics toolkit implementation.
    
    Scoring:
    - 28 tests total.
    - Each passed test is worth ~3.5 points (Max 98).
    - Bonus 2 points for 0 stubs remaining.
    - Penalty for test tampering (-50).
    - Penalty for "Do Nothing" (0 passed).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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

    # Extract metrics
    tests_passed = result.get('tests_passed', 0)
    tests_failed = result.get('tests_failed', 0)
    total_tests = result.get('total_tests', 0) # Should be 28
    tests_tampered = result.get('tests_tampered', False)
    stubs_remaining = result.get('stubs_remaining_count', 9)
    passed_names = result.get('passed_test_names', [])
    
    # Calculate Score
    score = 0
    feedback = []

    # 1. Base Score from Tests
    # Weights for specific modules based on passed_names analysis could be done here,
    # but simple per-test scoring is robust enough.
    points_per_test = 100.0 / 28.0 
    score += tests_passed * points_per_test
    
    feedback.append(f"Tests Passed: {tests_passed}/{total_tests}")

    # 2. Stub Penalty/Bonus
    if stubs_remaining == 0 and tests_passed > 0:
        # Round up to nice number if perfect
        if tests_passed == 28:
            score = 100
        feedback.append("All function stubs implemented.")
    elif stubs_remaining > 0:
        feedback.append(f"{stubs_remaining} functions still raise NotImplementedError.")

    # 3. Anti-Gaming Penalties
    if tests_tampered:
        score = 0
        feedback.append("CRITICAL: Test file tampering detected. Score reset to 0.")
    
    # 4. Check for 'Do Nothing'
    if tests_passed == 0:
        score = 0
        feedback.append("No tests passed.")

    # Cap score
    score = min(100, max(0, int(score)))
    
    # Pass Threshold
    passed = score >= task_info.get('metadata', {}).get('pass_threshold', 60)

    # Detailed Feedback
    if passed:
        feedback.insert(0, "TASK PASSED")
    else:
        feedback.insert(0, "TASK FAILED")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "tests_passed": tests_passed,
            "tests_failed": tests_failed,
            "stubs_remaining": stubs_remaining,
            "tampered": tests_tampered
        }
    }