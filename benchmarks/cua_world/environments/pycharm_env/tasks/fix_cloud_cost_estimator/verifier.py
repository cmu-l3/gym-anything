#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_cloud_cost_estimator(traj, env_info, task_info):
    """
    Verify the fix_cloud_cost_estimator task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    task_name = "fix_cloud_cost_estimator"
    result_path = f"/tmp/{task_name}_result.json"
    
    # Retrieve result file
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        
        copy_from_env(result_path, tmp_path)
        
        with open(tmp_path, 'r') as f:
            result = json.load(f)
            
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}

    score = 0
    feedback_parts = []
    
    # Criterion 1: Tiered Pricing Fix (35 pts)
    # Critical bug. Must pass test_tiered_pricing_cumulative.
    if result.get('test_transfer_pass', False):
        score += 35
        feedback_parts.append("Tiered pricing logic fixed (35/35)")
    else:
        feedback_parts.append("Tiered pricing test failed")

    # Criterion 2: Unit Conversion Fix (30 pts)
    # Must pass test_storage_gb_to_gib_conversion.
    if result.get('test_storage_pass', False):
        score += 30
        feedback_parts.append("Unit conversion logic fixed (30/30)")
    else:
        feedback_parts.append("Unit conversion test failed")

    # Criterion 3: Region Matching Fix (25 pts)
    # Must pass test_region_lookup_with_az.
    if result.get('test_region_pass', False):
        score += 25
        feedback_parts.append("Region lookup logic fixed (25/25)")
    else:
        feedback_parts.append("Region lookup test failed")

    # Criterion 4: No Regression (10 pts)
    # All tests passed implies no regression on basic tests too.
    # We check if tests_failed is 0 and at least 3 tests passed (the 3 fixes).
    tests_passed = result.get('tests_passed', 0)
    tests_failed = result.get('tests_failed', 0)
    
    if tests_failed == 0 and tests_passed >= 5:
        score += 10
        feedback_parts.append("No regressions (10/10)")
    elif tests_failed > 0:
        feedback_parts.append(f"{tests_failed} tests failed")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }