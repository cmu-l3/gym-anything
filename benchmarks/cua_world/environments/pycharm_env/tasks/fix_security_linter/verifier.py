#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_security_linter(traj, env_info, task_info):
    """
    Verify the fix_security_linter task.
    
    Scoring Criteria:
    1. Bug 1 Fixed (Recursion/Nested Eval): 30 pts
    2. Bug 2 Fixed (False Positive Secrets): 30 pts
    3. Bug 3 Fixed (Shell=True Logic): 30 pts
    4. No Regressions (All tests pass): 10 pts
    
    The verifier checks both the test results (behavioral) and code patterns (static analysis).
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    task_name = "fix_security_linter"
    result_path = f"/tmp/{task_name}_result.json"
    
    # Retrieve result file
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env(result_path, tmp_path)
            with open(tmp_path, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in environment"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Result file is malformed JSON"}

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Bug 1 (Recursion) ---
    # We require the test 'test_detect_nested_eval' to pass.
    # Code check is supplementary evidence.
    if result.get("test_nested_eval_pass", False):
        score += 30
        feedback_parts.append("Bug 1 Fixed: Nested eval() detected (recursion added).")
    else:
        feedback_parts.append("Bug 1 Failed: 'test_detect_nested_eval' failing. Recursion likely missing in visit_FunctionDef.")

    # --- Criterion 2: Bug 2 (False Positives) ---
    # We require 'test_safe_password_assignment' to pass.
    if result.get("test_safe_pwd_pass", False):
        score += 30
        feedback_parts.append("Bug 2 Fixed: Safe password assignments no longer flagged.")
    else:
        feedback_parts.append("Bug 2 Failed: 'test_safe_password_assignment' failing. Linter likely flagging variable names without checking values.")

    # --- Criterion 3: Bug 3 (Shell=True) ---
    # We require 'test_subprocess_shell_true' to pass.
    # Note: If this passes but bug3_shell_check_fixed (regex) is false, 
    # the agent might have fixed it in a way regex didn't catch, which is fine if tests pass.
    if result.get("test_shell_true_pass", False):
        score += 30
        feedback_parts.append("Bug 3 Fixed: subprocess(shell=True) correctly identified.")
    else:
        feedback_parts.append("Bug 3 Failed: 'test_subprocess_shell_true' failing. AST boolean check logic likely incorrect.")

    # --- Criterion 4: Overall Health ---
    tests_passed = result.get("tests_passed", 0)
    tests_total = result.get("tests_total", 0)
    
    if result.get("all_tests_pass", False):
        score += 10
        feedback_parts.append("All tests passed (No regressions).")
    else:
        feedback_parts.append(f"Regressions detected: Only {tests_passed}/{tests_total} tests passed.")

    # Sanity Check on Test File
    # If the test file size is suspiciously small (e.g., < 500 bytes), user might have deleted tests
    test_file_size = result.get("test_file_size", 0)
    if test_file_size < 500:
        score = 0
        feedback_parts = ["CRITICAL: Test file appears truncated or deleted. Score reset to 0."]

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }