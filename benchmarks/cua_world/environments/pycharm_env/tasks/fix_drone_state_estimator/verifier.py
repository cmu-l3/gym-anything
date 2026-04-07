#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_drone_state_estimator(traj, env_info, task_info):
    """
    Verify the fix_drone_state_estimator task.
    Scoring:
    - Bug 1 (Time Integration): 25 pts (Verified via test_predict_constant_velocity or code check)
    - Bug 2 (Measurement Matrix): 25 pts (Verified via test_gps_update_matrix or code check)
    - Bug 3 (Covariance Sign): 25 pts (Verified via test_covariance_reduction or code check)
    - Trajectory Accuracy: 25 pts (RMSE < 1.0m)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    task_name = "fix_drone_state_estimator"
    result_path = f"/tmp/{task_name}_result.json"
    
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env(result_path, tmp_path)
            with open(tmp_path, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    score = 0
    feedback = []
    
    # Check Bug 1: Time Integration
    if result.get('pass_predict') or result.get('code_fix_1'):
        score += 25
        feedback.append("Bug 1 Fixed: Time integration logic corrected.")
    else:
        feedback.append("Bug 1 Failed: Position prediction still ignores dt.")

    # Check Bug 2: Measurement Matrix
    if result.get('pass_matrix') or result.get('code_fix_2'):
        score += 25
        feedback.append("Bug 2 Fixed: GPS measurement matrix H corrected.")
    else:
        feedback.append("Bug 2 Failed: H matrix still maps velocity instead of position.")

    # Check Bug 3: Covariance Update
    if result.get('pass_cov') or result.get('code_fix_3'):
        score += 25
        feedback.append("Bug 3 Fixed: Covariance update sign error corrected.")
    else:
        feedback.append("Bug 3 Failed: Covariance update not reducing uncertainty.")

    # Check Trajectory Accuracy
    try:
        rmse = float(result.get('rmse', 999.0))
    except (ValueError, TypeError):
        rmse = 999.0
        
    if rmse < 1.0:
        score += 25
        feedback.append(f"Trajectory Accuracy: RMSE {rmse:.2f}m is excellent (<1.0m).")
    elif rmse < 5.0:
        score += 10
        feedback.append(f"Trajectory Accuracy: RMSE {rmse:.2f}m is fair (<5.0m), but could be better.")
    else:
        feedback.append(f"Trajectory Accuracy: RMSE {rmse:.2f}m is too high (Diverged).")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }