#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_debug_multithreaded_processor(traj, env_info, task_info):
    """
    Verify the fix for race conditions and deadlocks.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    task_name = "debug_multithreaded_processor"
    result_path = f"/tmp/{task_name}_result.json"
    
    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Race Condition Fix (40 pts)
    if result.get('balance_test_passed', False):
        score += 40
        feedback_parts.append("Race condition fixed (Data Integrity Verified)")
    else:
        feedback_parts.append("Race condition persists (Lost Updates detected)")

    # 2. Deadlock Fix (40 pts)
    stress_passed = result.get('stress_test_passed', False)
    stress_status = result.get('stress_test_status', 'UNKNOWN')
    
    if stress_passed:
        score += 40
        feedback_parts.append("Deadlock fixed (System Stability Verified)")
    elif stress_status == "TIMEOUT_DETECTED":
        feedback_parts.append("Deadlock persists (Stress test timed out/hung)")
    else:
        feedback_parts.append("Stress test failed (Assertion error or crash)")

    # 3. Code Quality / Static Checks (20 pts)
    # Check if Account uses locks (10 pts)
    if result.get('lock_used_in_account', False):
        score += 10
        feedback_parts.append("Lock usage detected in Account")
    else:
        feedback_parts.append("No lock usage detected in Account class")

    # Check for lock ordering (10 pts)
    if result.get('lock_ordering_detected', False):
        score += 10
        feedback_parts.append("Lock ordering logic detected")
    else:
        feedback_parts.append("No lock ordering logic detected (potential random deadlock fix?)")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }