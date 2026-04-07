#!/usr/bin/env python3
import json
import os
import tempfile

def verify_fix_delivery_router(traj, env_info, task_info):
    """
    Verify fixes for the delivery router task.
    
    Criteria:
    1. Bug 1 (Distance/Radians): 30 pts
    2. Bug 2 (Solver/Infinite Loop): 35 pts
    3. Bug 3 (Return to Depot): 25 pts
    4. Clean Execution (All tests pass): 10 pts
    
    Pass threshold: 65 pts
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env not available"
        }
        
    task_name = "fix_delivery_router"
    result_path = f"/tmp/{task_name}_result.json"
    
    # Retrieve result file
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
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to retrieve or parse result: {e}"
        }
        
    score = 0
    feedback = []
    
    # Score Bug 1
    if result.get("bug1_radians_fixed"):
        score += 30
        feedback.append("Fixed Haversine radians conversion (+30)")
    else:
        feedback.append("Failed to fix Haversine distance calculation")
        
    # Score Bug 2
    if result.get("bug2_solver_logic_fixed"):
        score += 35
        feedback.append("Fixed Greedy Solver infinite loop/visited logic (+35)")
    else:
        feedback.append("Failed to fix Solver logic (infinite loop or duplicates)")
        
    # Score Bug 3
    if result.get("bug3_return_leg_fixed"):
        score += 25
        feedback.append("Fixed Return-to-Depot distance calculation (+25)")
    else:
        feedback.append("Failed to include return leg in total distance")
        
    # Score Clean Execution
    if result.get("all_tests_pass"):
        score += 10
        feedback.append("All tests passed cleanly (+10)")
        
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }