#!/usr/bin/env python3
import json
import os
import tempfile

def verify_implement_code_metrics(traj, env_info, task_info):
    """
    Verify implementation of code metrics library.
    
    Scoring:
    - 60 points: Passing public tests (proportional to pass rate)
    - 20 points: Secret validation (generalization check)
    - 10 points: Anti-gaming (AST usage)
    - 10 points: All tests passing bonus
    
    Pass threshold: 60/100
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env"}
        
    task_name = "implement_code_metrics"
    result_path = f"/tmp/{task_name}_result.json"
    
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
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
        
    score = 0
    feedback = []
    
    # 1. Public Tests (Max 60)
    passed_tests = result.get("tests_passed", 0)
    failed_tests = result.get("tests_failed", 0)
    total_tests = passed_tests + failed_tests
    
    if total_tests > 0:
        test_score = int((passed_tests / 24.0) * 60) # Approx 24 tests expected
        test_score = min(60, test_score)
        score += test_score
        feedback.append(f"Public Tests: {passed_tests}/{total_tests} passed ({test_score}/60 pts)")
    else:
        feedback.append("No tests ran.")
        
    # 2. Secret Validation (Max 20)
    secret = result.get("secret_validation", {})
    if secret.get("loc_ok") and secret.get("comp_ok"):
        score += 20
        feedback.append("Secret Validation: Passed (20/20 pts)")
    elif secret.get("error"):
        feedback.append(f"Secret Validation: Error - {secret['error']}")
    else:
        feedback.append(f"Secret Validation: Failed (LOC: {secret.get('loc_ok')}, Comp: {secret.get('comp_ok')})")
        
    # 3. Anti-gaming (Max 10)
    if result.get("ast_imported"):
        score += 10
        feedback.append("Architecture: AST module used (10/10 pts)")
    else:
        feedback.append("Architecture: AST module NOT used (0/10 pts)")
        
    # 4. Completion Bonus (Max 10)
    if result.get("all_tests_pass") and total_tests >= 20:
        score += 10
        feedback.append("Bonus: All tests passed (10/10 pts)")
        
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }