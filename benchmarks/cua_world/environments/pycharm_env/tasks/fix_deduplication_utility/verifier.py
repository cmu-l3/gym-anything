#!/usr/bin/env python3
"""
Verifier for fix_deduplication_utility task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_deduplication_utility(traj, env_info, task_info):
    """
    Verify fixes for smart_dedup.py bugs.
    
    Scoring:
    1. Integrity Bug (Partial Hashing) Fixed: 35 pts
    2. Crash Bug (Linking) Fixed: 30 pts
    3. Logic Bug (Small Files) Fixed: 20 pts
    4. All Tests Pass: 15 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Integrity Fix (35 pts)
    # Critical: Must pass the collision test. 
    # Static analysis is a weak signal (can fix logic without specific keywords), so rely mostly on test.
    if result.get('test_integrity_pass', False):
        score += 35
        feedback_parts.append("Integrity Fix: PASSED (Files with identical headers handled correctly)")
    else:
        feedback_parts.append("Integrity Fix: FAILED (Partial hashing still causing collisions)")

    # 2. Crash Fix (30 pts)
    # Critical: Must handle existing destination files.
    if result.get('test_crash_pass', False):
        score += 30
        feedback_parts.append("Crash Fix: PASSED (Existing files handled safely during linking)")
    else:
        feedback_parts.append("Crash Fix: FAILED (Script crashes when target file exists)")

    # 3. Small Files Fix (20 pts)
    if result.get('test_small_pass', False):
        score += 20
        feedback_parts.append("Logic Fix: PASSED (Small files are now processed)")
    else:
        feedback_parts.append("Logic Fix: FAILED (Small files still ignored)")

    # 4. Overall Health (15 pts)
    # Reward if ALL tests passed (implies no regressions)
    tests_failed = result.get('tests_failed', 0)
    pytest_exit = result.get('pytest_exit_code', 1)
    
    if pytest_exit == 0 and tests_failed == 0:
        score += 15
        feedback_parts.append("Regression Check: PASSED (All tests passing)")
    elif tests_failed > 0:
        feedback_parts.append(f"Regression Check: FAILED ({tests_failed} tests failed)")

    # Pass Threshold
    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }