#!/usr/bin/env python3
import json
import os
import tempfile

def verify_fix_meeting_scheduler(traj, env_info, task_info):
    """
    Verify that the meeting scheduler bugs are fixed.
    
    Scoring:
    - Bug 1 (Overlap): 35 pts (Tests pass + Logic check)
    - Bug 2 (Working Hours): 35 pts (Tests pass + Logic check)
    - Bug 3 (Future Check): 20 pts (Test pass + Logic check)
    - No Regression: 10 pts (All tests pass)
    
    Pass threshold: 90/100
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
        
    task_name = "fix_meeting_scheduler"
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
        
    score = 0
    feedback = []
    
    # Bug 1: Overlap
    # Require test pass. Static fix is bonus confidence but not strict requirement if test passes.
    if result.get("bug1_overlap_test_pass"):
        score += 35
        feedback.append("Overlap bug fixed (enclosing intervals detected).")
    else:
        feedback.append("Overlap bug NOT fixed: Enclosing interval tests failed.")
        
    # Bug 2: Working Hours (Timezones)
    if result.get("bug2_timezone_test_pass"):
        score += 35
        feedback.append("Timezone bug fixed (working hours validated in user timezone).")
    else:
        feedback.append("Timezone bug NOT fixed: Tokyo/London working hour tests failed.")
        
    # Bug 3: Future Check (Naive vs Aware)
    if result.get("bug3_future_test_pass"):
        score += 20
        feedback.append("Future validation bug fixed (timezone-aware comparison).")
    else:
        feedback.append("Future validation bug NOT fixed: TypeError on datetime comparison.")
        
    # No Regression
    # We give points if ALL tests passed (implying no regressions + bugs fixed)
    # Or specifically if the 'regression_pass' flag is true (which means all tests passed)
    if result.get("regression_pass"):
        score += 10
        feedback.append("No regressions detected.")
    else:
        # If we fixed bugs but broke others, we lose these points
        if score > 0:
            feedback.append("Warning: Some regressions detected (not all tests passed).")
            
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }