#!/usr/bin/env python3
import json
import os
import tempfile

def verify_fix_feature_flag_engine(traj, env_info, task_info):
    """
    Verify the feature flag engine fixes.
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
    
    # 1. Float Parsing (30 pts)
    if result.get('bug1_float_fixed'):
        score += 30
        feedback.append("Lexer correctly handles floating point numbers.")
    else:
        feedback.append("Lexer still fails on floats (Bug 1).")

    # 2. Precedence (30 pts)
    if result.get('bug2_precedence_fixed'):
        score += 30
        feedback.append("Parser correctly handles operator precedence (AND > OR).")
    else:
        feedback.append("Parser precedence is still incorrect (Bug 2).")

    # 3. Short Circuit (30 pts)
    if result.get('bug3_short_circuit_fixed'):
        score += 30
        feedback.append("Evaluator correctly short-circuits logic operations.")
    else:
        feedback.append("Evaluator crashes on unsafe operations (missing short-circuit) (Bug 3).")

    # 4. No Regressions (10 pts)
    # If all tests passed (and there are tests), give points
    passed_count = result.get('tests_passed_count', 0)
    failed_count = result.get('tests_failed_count', 0)
    
    if passed_count > 0 and failed_count == 0:
        score += 10
        feedback.append(f"All {passed_count} tests passed.")
    else:
        feedback.append(f"Some tests failed ({failed_count} failures).")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }