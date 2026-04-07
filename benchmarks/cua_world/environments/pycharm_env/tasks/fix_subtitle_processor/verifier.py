#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_subtitle_processor(traj, env_info, task_info):
    """
    Verify that the agent fixed 3 bugs in subtitle_processor.
    
    Scoring:
    - Bug 1 (Timestamp Math): 30 pts
    - Bug 2 (Framerate Logic): 30 pts
    - Bug 3 (Parser EOF): 20 pts
    - No Regression: 20 pts (implied if all tests pass)
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    task_name = "fix_subtitle_processor"
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    score = 0
    feedback = []
    
    # Bug 1: Timestamp Rollover
    if result.get("bug1_test_pass"):
        score += 30
        feedback.append("Bug 1 Fixed: Timestamp arithmetic correctly handles minute rollover.")
    elif result.get("bug1_code_check"):
        score += 15
        feedback.append("Bug 1 Partial: Code looks correct but test failed.")
    else:
        feedback.append("Bug 1 Failed: Timestamp arithmetic still incorrect.")

    # Bug 2: Framerate Conversion
    if result.get("bug2_test_pass"):
        score += 30
        feedback.append("Bug 2 Fixed: Framerate conversion ratio inverted correctly.")
    elif result.get("bug2_code_check"):
        score += 15
        feedback.append("Bug 2 Partial: Code looks correct but test failed.")
    else:
        feedback.append("Bug 2 Failed: Framerate conversion logic still incorrect.")

    # Bug 3: Parser EOF
    if result.get("bug3_test_pass"):
        score += 20
        feedback.append("Bug 3 Fixed: Parser correctly handles files without trailing newlines.")
    else:
        feedback.append("Bug 3 Failed: Parser drops last block if file doesn't end with newline.")

    # Regression Check / Full Pass
    # If all tests passed (exit code 0), full marks + bonus
    if result.get("pytest_exit_code") == 0:
        score = 100
        feedback.append("All tests passed! No regressions.")
    else:
        # Check if we broke anything else
        passed_count = result.get("tests_passed_count", 0)
        # We know there are 12 tests total. 
        if passed_count == 12: 
            score = 100 # Catch-case if exit code wasn't 0 for some system reason but tests passed
        elif passed_count < 6: # Initially 6 passed. If fewer pass now, regression.
            score = max(0, score - 10)
            feedback.append("REGRESSION DETECTED: Previously passing tests are now failing.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }