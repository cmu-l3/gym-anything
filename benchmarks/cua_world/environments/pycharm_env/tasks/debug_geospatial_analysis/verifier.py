#!/usr/bin/env python3
"""
Verifier for debug_geospatial_analysis task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_debug_geospatial_analysis(traj, env_info, task_info):
    """
    Verify the agent fixed 4 geospatial analysis bugs.
    
    Scoring:
    - 25 pts: Haversine formula fixed (geo.py)
    - 25 pts: DataFrame sorting fixed (processing.py)
    - 25 pts: Speed unit conversion fixed (metrics.py)
    - 25 pts: Outlier filter logic fixed (metrics.py)
    
    Verification uses both test results and code pattern matching.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    code_checks = result.get("code_checks", {})
    test_details = result.get("test_details", {})
    
    # Bug 1: Haversine
    # Criteria: Test passed OR code has 'radians'
    if test_details.get("geo_pass") or code_checks.get("geo_radians_found"):
        score += 25
        feedback.append("[PASS] Haversine formula fixed (degrees->radians)")
    else:
        feedback.append("[FAIL] Haversine formula incorrect")

    # Bug 2: Sorting
    # Criteria: Test passed OR code has 'sort_values'
    if test_details.get("sort_pass") or code_checks.get("processing_sort_found"):
        score += 25
        feedback.append("[PASS] Processing pipeline sorts by timestamp")
    else:
        feedback.append("[FAIL] Data not sorted before diff()")

    # Bug 3: Speed Units
    # Criteria: Test passed OR code has factor 3.6
    if test_details.get("units_pass") or code_checks.get("metrics_conversion_found"):
        score += 25
        feedback.append("[PASS] Speed calculated in km/h")
    else:
        feedback.append("[FAIL] Speed unit error (likely m/s instead of km/h)")

    # Bug 4: Filter Logic
    # Criteria: Test passed OR code check
    if test_details.get("filter_pass") or code_checks.get("metrics_filter_fixed"):
        score += 25
        feedback.append("[PASS] Outlier filter correctly preserves congestion")
    else:
        feedback.append("[FAIL] Congestion (low speed) still being filtered out")

    # Check for total regression (deleting all tests)
    total_tests = result.get("tests_total", 0)
    passed_tests = result.get("tests_passed", 0)
    
    if total_tests < 10:
         score = 0
         feedback.append("CRITICAL: Test suite seems truncated/deleted.")
    
    # Calculate Final
    pass_threshold = task_info.get("metadata", {}).get("pass_threshold", 75)
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback),
        "details": result
    }