#!/usr/bin/env python3
import json
import os
import tempfile

def verify_fix_3d_bin_packer(traj, env_info, task_info):
    """
    Verify fixes for 3D bin packer bugs.
    1. Geometry Z-axis fix (30 pts)
    2. Rotation state fix (30 pts)
    3. Strategy heuristic fix (30 pts)
    4. No regression (10 pts)
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    result_path = "/tmp/fix_3d_bin_packer_result.json"
    
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env(result_path, tmp_path)
            with open(tmp_path, "r") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []

    # Criterion 1: Geometry Fix
    if result.get("bug1_fixed") or result.get("test_geo_pass"):
        score += 30
        feedback.append("Geometry Z-axis intersection fixed.")
    else:
        feedback.append("Geometry Z-axis bug NOT fixed.")

    # Criterion 2: Rotation Fix
    if result.get("bug3_fixed") or result.get("test_rot_pass"):
        score += 30
        feedback.append("Item rotation state update fixed.")
    else:
        feedback.append("Item rotation bug NOT fixed.")

    # Criterion 3: Strategy Fix
    if result.get("bug2_fixed"):
        score += 30
        feedback.append("Packing heuristic sorted by Volume Descending.")
    else:
        feedback.append("Packing heuristic NOT fixed (check sort key and order).")

    # Criterion 4: Regression (All tests pass)
    tests_passed = result.get("tests_passed", 0)
    tests_failed = result.get("tests_failed", 0)
    
    if tests_passed > 0 and tests_failed == 0 and result.get("pytest_exit_code") == 0:
        score += 10
        feedback.append("All tests passed (No regression).")
    elif tests_failed > 0:
        feedback.append(f"{tests_failed} tests still failing.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }