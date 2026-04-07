#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_debug_invoice_generator(traj, env_info, task_info):
    """
    Verify the Invoice Generator Debugging Task.
    
    Scoring:
    - Math Fix (35 pts): test_math.py passes + Decimal used
    - Privacy Fix (35 pts): test_privacy.py passes
    - Layout Fix (30 pts): test_layout.py passes
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract metrics
    passed_tests = int(result.get('tests_passed', 0))
    failed_tests = int(result.get('tests_failed', 0))
    decimal_used = result.get('decimal_used', False)
    
    # Calculate score based on test output mapping (approximate based on test names implied)
    # Since we don't have per-test granularity in the simple export script, 
    # we assume uniform distribution if full json report isn't available.
    # However, let's look at the static flags for confirmation.
    
    score = 0
    feedback = []

    # Criteria 1: Math Fix (35 pts)
    # We rely on tests passing mainly, but static check confirms correct approach.
    # There are 4 math tests.
    math_score = 0
    if decimal_used:
        math_score += 10
    
    # If all tests passed (12 total), we assume math tests passed
    if passed_tests == 12:
        math_score = 35
    elif passed_tests >= 4 and decimal_used:
        # Partial credit heuristic
        math_score = 35
    
    score += math_score
    if math_score == 35:
        feedback.append("Math/Decimal fix verified.")
    else:
        feedback.append("Math fix incomplete or Decimal not used.")

    # Criteria 2: Privacy Fix (35 pts)
    # 4 privacy tests.
    privacy_score = 0
    if passed_tests == 12:
        privacy_score = 35
    elif result.get('masking_fixed', False) and passed_tests >= 8:
         privacy_score = 35
         
    score += privacy_score
    if privacy_score == 35:
        feedback.append("Privacy/Masking fix verified.")
    else:
        feedback.append("Privacy fix incomplete.")

    # Criteria 3: Layout Fix (30 pts)
    # 4 layout tests.
    layout_score = 0
    if passed_tests == 12:
        layout_score = 30
    elif result.get('layout_fixed', False) and passed_tests >= 8:
        layout_score = 30
        
    score += layout_score
    if layout_score == 30:
        feedback.append("Layout/Pagination fix verified.")
    else:
        feedback.append("Layout fix incomplete.")

    # Strict pass/fail
    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }