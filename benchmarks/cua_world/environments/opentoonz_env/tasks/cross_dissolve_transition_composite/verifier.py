#!/usr/bin/env python3
"""
Verifier for cross_dissolve_transition_composite task.

Scoring Criteria:
1. Frame Count (15 pts): Exactly 24 frames output.
2. Start/End Accuracy (40 pts): Frame 1 matches Day, Frame 24 matches Night.
3. Midpoint Blend (25 pts): Frame 12 matches 50/50 blend.
4. Smoothness (20 pts): Transition is monotonic (not a hard cut).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cross_dissolve(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Result JSON
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
    feedback_parts = []
    
    # Analysis Data from export_result.sh
    analysis = result.get("analysis", {})
    file_count = result.get("file_count", 0)
    new_files = result.get("new_files_count", 0)
    
    # 1. Frame Count & Existence (15 pts)
    # Task requires exactly 24 frames for a 24-frame transition
    if file_count == 24:
        score += 15
        feedback_parts.append("Frame count correct (24)")
    elif file_count >= 24:
        score += 10
        feedback_parts.append(f"Frame count sufficient ({file_count})")
    elif file_count > 0:
        score += 5
        feedback_parts.append(f"Incomplete frame count ({file_count}/24)")
    else:
        return {"passed": False, "score": 0, "feedback": "No output frames found"}

    # Anti-gaming: Files must be new
    if new_files < file_count:
        feedback_parts.append("Warning: Some files pre-dated task start")
    
    # 2. Endpoint Accuracy (40 pts)
    # MSE threshold. 0 is perfect. < 50 is usually acceptable for compression artifacts.
    # The setup uses PNG, so compression should be lossless, allowing tight thresholds.
    mse_threshold = task_info.get("metadata", {}).get("mse_threshold", 50.0)
    
    start_mse = analysis.get("start_mse", 9999)
    end_mse = analysis.get("end_mse", 9999)
    
    if start_mse < mse_threshold:
        score += 20
        feedback_parts.append(f"Start frame matches source (MSE: {start_mse:.2f})")
    else:
        feedback_parts.append(f"Start frame mismatch (MSE: {start_mse:.2f})")
        
    if end_mse < mse_threshold:
        score += 20
        feedback_parts.append(f"End frame matches source (MSE: {end_mse:.2f})")
    else:
        feedback_parts.append(f"End frame mismatch (MSE: {end_mse:.2f})")

    # 3. Midpoint Blend (25 pts)
    # Frame 12 should be 50% Day + 50% Night. 
    mid_mse = analysis.get("mid_mse", 9999)
    
    if mid_mse < mse_threshold:
        score += 25
        feedback_parts.append(f"Midpoint blend correct (MSE: {mid_mse:.2f})")
    elif mid_mse < mse_threshold * 2:
        score += 15
        feedback_parts.append(f"Midpoint blend acceptable (MSE: {mid_mse:.2f})")
    else:
        feedback_parts.append(f"Midpoint blend incorrect (MSE: {mid_mse:.2f}) - likely a hard cut or wrong timing")

    # 4. Smoothness / Monotonicity (20 pts)
    # Ensures the transition happens over time, not just frame 1->2.
    monotonicity = analysis.get("monotonicity_score", 0)
    if monotonicity > 0.9:
        score += 20
        feedback_parts.append("Transition is smooth")
    else:
        feedback_parts.append("Transition is not smooth or monotonic")

    # Final Result
    passed = score >= 65 and file_count >= 24
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }