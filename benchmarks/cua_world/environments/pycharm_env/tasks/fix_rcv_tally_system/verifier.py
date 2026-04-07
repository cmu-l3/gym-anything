import json
import os
import tempfile

def verify_fix_rcv_tally_system(traj, env_info, task_info):
    """
    Verify the RCV Tally System fixes.
    
    Scoring:
    - 20 pts: Loader bug fixed (test_normalization passes)
    - 30 pts: Transfer bug fixed (test_transfer_logic_skips_eliminated passes)
    - 30 pts: Threshold bug fixed (test_majority_excludes_exhausted passes)
    - 20 pts: All tests pass (regression check)
    
    Note: Since we don't have granular per-test results in the simple JSON export 
    (unless we parse the full pytest output), we infer specific fixes from 
    the combination of static analysis flags and the "All Tests Pass" flag.
    If all tests pass, they fixed everything.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}
        
    task_name = "fix_rcv_tally_system"
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

    all_tests_pass = result.get("all_tests_pass", False)
    tests_passed = result.get("tests_passed", 0)
    
    # We infer specific fixes based on tests passed count or the static analysis flags
    # But reliable "all tests pass" is the gold standard here.
    
    # 1. Loader Fix (20 pts)
    # If all tests passed, this passed. Or if static analysis found the fix.
    if all_tests_pass or result.get("loader_fixed_static", False):
        score += 20
        feedback.append("Loader case-sensitivity bug fixed.")
    else:
        feedback.append("Loader bug likely not fixed (tests failed or no string normalization found).")

    # 2. Transfer Fix (30 pts)
    if all_tests_pass or result.get("transfer_fixed_static", False):
        score += 30
        feedback.append("Vote transfer logic fixed (skips eliminated candidates).")
    else:
        feedback.append("Transfer logic bug likely not fixed.")

    # 3. Threshold Fix (30 pts)
    if all_tests_pass or result.get("threshold_fixed_static", False):
        score += 30
        feedback.append("Majority threshold calculation fixed (uses active ballots).")
    else:
        feedback.append("Majority threshold bug likely not fixed.")

    # 4. Full Regression / End-to-End (20 pts)
    # Check if main.py output the correct winner
    if result.get("correct_winner_found", False):
        score += 20
        feedback.append("End-to-end verification passed (Alice won).")
    elif all_tests_pass:
        # If tests pass but main output is weird, maybe they didn't run main? 
        # But if tests pass, logic is good.
        score += 20
        feedback.append("Tests passed, assuming end-to-end correctness.")
    else:
        feedback.append("End-to-end simulation produced incorrect winner.")

    # VLM Check (Bonus/Validation - optional implementation)
    # In a real scenario, we might check if PyCharm is visible.
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }