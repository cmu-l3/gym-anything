#!/usr/bin/env python3
"""
Verifier for fix_barcode_encoder task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_barcode_encoder(traj, env_info, task_info):
    """
    Verify that the 3 barcode encoder bugs were fixed.
    
    Criteria:
    1. UPC Checksum Fixed (30 pts)
    2. Code128 Modulo Fixed (30 pts)
    3. Code128 Stop Pattern Fixed (30 pts)
    4. No Regressions (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    result_path = "/tmp/fix_barcode_encoder_result.json"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env(result_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    # 1. UPC Checksum
    if result.get("upc_checksum_fixed", False):
        score += 30
        feedback.append("UPC Checksum fixed (30/30)")
    else:
        feedback.append("UPC Checksum NOT fixed (0/30)")
        
    # 2. Code 128 Modulo
    if result.get("code128_mod_fixed", False):
        score += 30
        feedback.append("Code 128 Modulo fixed (30/30)")
    else:
        feedback.append("Code 128 Modulo NOT fixed (0/30)")
        
    # 3. Code 128 Stop Pattern
    if result.get("code128_stop_fixed", False):
        score += 30
        feedback.append("Code 128 Stop Pattern fixed (30/30)")
    else:
        feedback.append("Code 128 Stop Pattern NOT fixed (0/30)")
        
    # 4. Regressions/Total
    tests_passed = result.get("tests_passed", 0)
    tests_failed = result.get("tests_failed", 0)
    
    # Assuming expected total is around 11 tests (based on conftest setup)
    # The setup script creates:
    # - test_upc.py: 5 tests
    # - test_code128.py: 4 tests
    # Total 9 tests. 
    # If all pass, we award the final 10 points.
    
    if tests_failed == 0 and tests_passed > 0:
        score += 10
        feedback.append("All tests passed (10/10)")
    else:
        feedback.append(f"Some tests failed: {tests_failed} failures")
        
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }