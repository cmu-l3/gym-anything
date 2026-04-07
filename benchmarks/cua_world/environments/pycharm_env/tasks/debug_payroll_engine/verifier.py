#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_debug_payroll_engine(traj, env_info, task_info):
    """
    Verifies the debug_payroll_engine task.
    
    Scoring Criteria:
    1. Pytest Results (40 pts): All tests passed.
    2. Currency Precision (20 pts): 'from decimal import Decimal' used.
    3. Hidden Validation (40 pts): 
       - Progressive Tax Logic (15 pts)
       - SS Cap Logic (10 pts)
       - Overtime Weekly Logic (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 1. Tests (40 pts)
    # Total tests in the provided setup:
    # test_currency (2), test_tax (3), test_overtime (1) = 6 tests.
    tests_passed = result.get("tests_passed", 0)
    tests_failed = result.get("tests_failed", 0)
    
    if tests_failed == 0 and tests_passed >= 4:
        score += 40
        feedback.append("All unit tests passed (40/40)")
    elif tests_passed > 0:
        partial = int((tests_passed / (tests_passed + tests_failed)) * 30)
        score += partial
        feedback.append(f"Some tests failed ({tests_passed} passed, {tests_failed} failed)")
    else:
        feedback.append("All tests failed")

    # 2. Currency Precision (20 pts)
    if result.get("uses_decimal", False):
        score += 20
        feedback.append("Decimal module used for currency (20/20)")
    else:
        feedback.append("Currency logic still uses floats (0/20)")

    # 3. Hidden Validation (40 pts)
    # hidden_score ranges 0-3 corresponding to the 3 checks
    hidden_score = result.get("hidden_score", 0)
    hidden_details = result.get("hidden_details", "")
    
    # Weighting: 
    # Check 1 (Tax): 15 pts
    # Check 2 (SS): 10 pts
    # Check 3 (OT): 15 pts
    # Since export script returns just count 0-3, we approximate or need granular export.
    # The export script calculates score as sum of 1s.
    # Let's trust the export script's integer count for simplicity in this generated code,
    # or map 1->13, 2->26, 3->40.
    
    if hidden_score == 3:
        score += 40
        feedback.append("Hidden dataset verification passed all checks (40/40)")
    elif hidden_score == 2:
        score += 25
        feedback.append("Hidden dataset verification passed 2/3 checks (25/40)")
    elif hidden_score == 1:
        score += 10
        feedback.append("Hidden dataset verification passed 1/3 checks (10/40)")
    else:
        feedback.append(f"Hidden dataset verification failed: {hidden_details}")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }