#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_3d_printer_slicer(traj, env_info, task_info):
    """
    Verify that the agent fixed the 3 bugs in the 3D slicer.
    
    Scoring:
    - Bug 1 (Crash/ZeroDivision): 30 pts
    - Bug 2 (Missing top layer): 30 pts
    - Bug 3 (Open loops): 30 pts
    - No Regressions / All Pass: 10 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    task_name = "fix_3d_printer_slicer"
    result_path = f"/tmp/{task_name}_result.json"

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env(result_path, tmp_path)
            with open(tmp_path, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    # Bug 1: Horizontal Intersection
    if result.get("bug1_fixed", False):
        score += 30
        feedback.append("Bug 1 (Horizontal Edge Crash) fixed.")
    else:
        feedback.append("Bug 1 NOT fixed: Test 'test_horizontal_intersection' failed.")

    # Bug 2: Layer Count
    if result.get("bug2_fixed", False):
        score += 30
        feedback.append("Bug 2 (Missing Top Layer) fixed.")
    else:
        feedback.append("Bug 2 NOT fixed: Test 'test_layer_count' failed (likely float precision issue).")

    # Bug 3: Perimeter Closure
    if result.get("bug3_fixed", False):
        score += 30
        feedback.append("Bug 3 (Open Loops) fixed.")
    else:
        feedback.append("Bug 3 NOT fixed: Test 'test_perimeter_closure' failed.")

    # All Pass Bonus
    if result.get("all_tests_pass", False):
        score += 10
        feedback.append("Bonus: All tests passed.")

    # Pass threshold
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }