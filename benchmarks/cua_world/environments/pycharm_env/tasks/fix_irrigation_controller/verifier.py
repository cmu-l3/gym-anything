#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_irrigation_controller(traj, env_info, task_info):
    """
    Verify the fix_irrigation_controller task.
    
    Criteria:
    1. Bug 1 (ETo Formula) Fixed: 30 pts
    2. Bug 2 (Rain Logic) Fixed: 30 pts
    3. Bug 3 (Sensor None) Fixed: 30 pts
    4. No Regressions (All tests pass): 10 pts
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # Load result
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_name = tmp.name
        copy_from_env("/tmp/task_result.json", tmp_name)
        with open(tmp_name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load results: {e}"}

    score = 0
    feedback = []

    # Bug 1: ETo
    # We rely primarily on the test passing, but use static analysis as backup/confirmation
    if result.get("test_eto_pass", False):
        score += 30
        feedback.append("Bug 1 (ETo Formula) fixed: Test passed.")
    elif result.get("bug1_fixed_static", False):
        score += 15 # Partial credit if test failed but code looks right? Rare.
        feedback.append("Bug 1 (ETo Formula): Static check passed, but test failed.")
    else:
        feedback.append("Bug 1 (ETo Formula) NOT fixed.")

    # Bug 2: Scheduler
    if result.get("test_scheduler_pass", False):
        score += 30
        feedback.append("Bug 2 (Rain Logic) fixed: Test passed.")
    else:
        feedback.append("Bug 2 (Rain Logic) NOT fixed.")

    # Bug 3: Sensors
    if result.get("test_sensors_pass", False):
        score += 30
        feedback.append("Bug 3 (Sensor Crash) fixed: Test passed.")
    else:
        feedback.append("Bug 3 (Sensor Crash) NOT fixed.")

    # Regressions
    if result.get("all_tests_pass", False):
        score += 10
        feedback.append("All tests passed (No regressions).")
    else:
        passed = result.get("tests_passed", 0)
        total = result.get("tests_total", 0)
        feedback.append(f"Some tests failed ({passed}/{total}).")

    return {
        "passed": score >= 90,
        "score": score,
        "feedback": " ".join(feedback)
    }