#!/usr/bin/env python3
"""Verifier for fix_thread_deadlock task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_fix_thread_deadlock(traj, env_info, task_info):
    """Verify that the deadlock was fixed and thread safety maintained.

    Criteria:
    1. Tests passed (Liveness): testDeadlockFreedom passed (40 pts)
    2. Tests passed (Safety): testThreadSafety passed (40 pts)
    3. Code Quality: Account.java still contains synchronization/locking (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Read result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # Extract data
    tests_run = result.get('tests_run', 0)
    tests_passed = result.get('tests_passed', 0)
    timeout_occurred = result.get('timeout_occurred', False)
    account_content = result.get('account_content', '')
    file_modified = result.get('file_modified', False)

    # --- Criterion 1 & 2: Tests Passed (80 pts) ---
    # We expect 2 tests total.
    if timeout_occurred:
        feedback_parts.append("Tests TIMED OUT - Deadlock likely still present")
        # Score remains 0 for tests
    elif tests_run == 2 and tests_passed == 2:
        score += 80
        feedback_parts.append("All tests passed (Deadlock fixed + Thread safe)")
    elif tests_run > 0:
        # Partial credit? Unlikely for deadlock, but maybe safety failed
        # If 1 passed, it's usually the safety one (if they didn't touch anything) 
        # or the deadlock one (if they removed locks but broke safety)
        score += int(80 * (tests_passed / 2))
        feedback_parts.append(f"{tests_passed}/{tests_run} tests passed")
    else:
        feedback_parts.append("No tests ran")

    # --- Criterion 3: Code Quality / Implementation Check (20 pts) ---
    # We want to ensure they didn't just delete 'synchronized' keywords to "fix" deadlock
    # (which would fail the safety test, but we want static analysis too).
    # OR they used Lock/ReentrantLock.
    
    has_sync = 'synchronized' in account_content
    has_lock = 'Lock' in account_content or 'ReentrantLock' in account_content
    
    # Check for lock ordering implementation details (heuristic)
    # Looking for comparison of IDs or System.identityHashCode
    has_ordering = (
        'id' in account_content and 
        ('>' in account_content or '<' in account_content or 'compareTo' in account_content)
    )

    if not file_modified:
         feedback_parts.append("Account.java was not modified")
    elif has_sync or has_lock:
        score += 20
        method = "synchronized blocks" if has_sync else "Locks"
        feedback_parts.append(f"Valid synchronization detected ({method})")
        
        if has_ordering:
            feedback_parts.append("(Appears to use lock ordering)")
    else:
        # If they removed all sync/locks, they might pass liveness but fail safety
        feedback_parts.append("WARNING: No synchronization/locks detected in code")

    # --- VLM Verification (Optional but recommended) ---
    # Using the gym_anything.vlm helpers if available
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Simple VLM check: Did they edit the code?
        # We assume if the programmatic check passes, they likely did, 
        # but VLM can confirm the IDE was used properly.
        # For now, we trust the programmatic tests as primary signal.
        pass
    except ImportError:
        pass

    # Final Score Calculation
    passed = score >= 80  # Must pass both tests
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }