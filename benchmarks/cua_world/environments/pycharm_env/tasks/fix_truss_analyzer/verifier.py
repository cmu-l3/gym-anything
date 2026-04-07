#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_truss_analyzer(traj, env_info, task_info):
    """
    Verify the fix_truss_analyzer task.
    
    Scoring:
    - Bug 1 (Area): 30 pts (Verified by test_element_area)
    - Bug 2 (Rotation): 30 pts (Verified by test_stiffness_matrix_vertical)
    - Bug 3 (Assembly): 30 pts (Verified by test_global_assembly_accumulation)
    - All Tests Pass: 10 pts
    
    Total: 100 pts.
    Threshold: 90 pts.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result file
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env("/tmp/task_result.json", tmp_path)
            with open(tmp_path, "r") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}

    score = 0
    feedback_parts = []
    
    # Check Bug 1: Area
    # Primary signal: test_geometry_pass
    # Secondary: area_heuristic_fixed
    if result.get("test_geometry_pass", False):
        score += 30
        feedback_parts.append("Bug 1 (Area) Fixed [Tests Passed]")
    elif result.get("area_heuristic_fixed", False):
        score += 15
        feedback_parts.append("Bug 1 (Area) partially fixed [Code changed but tests failing]")
    else:
        feedback_parts.append("Bug 1 (Area) FAILED")

    # Check Bug 2: Rotation Matrix
    # Primary: test_element_pass
    if result.get("test_element_pass", False):
        score += 30
        feedback_parts.append("Bug 2 (Rotation) Fixed [Tests Passed]")
    elif result.get("rotation_heuristic_fixed", False):
        score += 15
        feedback_parts.append("Bug 2 (Rotation) partially fixed [Code changed but tests failing]")
    else:
        feedback_parts.append("Bug 2 (Rotation) FAILED")

    # Check Bug 3: Assembly
    # Primary: test_solver_pass
    if result.get("test_solver_pass", False):
        score += 30
        feedback_parts.append("Bug 3 (Assembly) Fixed [Tests Passed]")
    elif result.get("assembly_heuristic_fixed", False):
        score += 15
        feedback_parts.append("Bug 3 (Assembly) partially fixed [Code changed but tests failing]")
    else:
        feedback_parts.append("Bug 3 (Assembly) FAILED")

    # Integration Check
    all_passed = result.get("all_tests_pass", False)
    if all_passed:
        score += 10
        feedback_parts.append("All Tests Passed (+10)")
    
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }