#!/usr/bin/env python3
"""
Verifier for create_mouse_tracking_task.

Scoring Criteria:
1. Valid Experiment File (10 pts): .psyexp exists and is valid XML.
2. Conditions File Created (10 pts): competitors.csv exists with correct columns.
3. Start/Home Routine (30 pts): A routine exists with a button at y=-0.7 and a mouse component.
4. Continuous Recording (50 pts): The Mouse component in the trial routine is set to save state "every frame".

Pass Threshold: 90 points (Strict: Must have continuous recording and start routine).
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_create_mouse_tracking_task(traj, env_info, task_info):
    """Verify the mouse tracking experiment creation."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    feedback_parts = []
    score = 0
    
    # Load result JSON
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/mouse_tracking_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if 'tmp_path' in locals() and os.path.exists(tmp_path):
            os.unlink(tmp_path)
            
    # Nonce check
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
            nonce_path = tmp.name
        copy_from_env("/home/ga/.task_nonce", nonce_path)
        with open(nonce_path, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "FAIL: Integrity check failed (nonce mismatch)"}
    except Exception:
        pass # Skip if nonce file missing in env (dev mode)
    finally:
        if 'nonce_path' in locals() and os.path.exists(nonce_path):
            os.unlink(nonce_path)

    # 1. Experiment File (10 pts)
    if result.get("exp_file_exists") and result.get("is_valid_xml"):
        score += 10
        feedback_parts.append("Experiment file valid")
    else:
        feedback_parts.append("Experiment file missing or invalid")
        
    # 2. Conditions File (10 pts)
    if result.get("cond_file_exists") and result.get("has_required_columns") and result.get("cond_row_count", 0) >= 4:
        score += 10
        feedback_parts.append("Conditions file valid")
    elif result.get("cond_file_exists"):
        score += 5
        feedback_parts.append("Conditions file exists but missing columns/rows")
    else:
        feedback_parts.append("Conditions file missing")
        
    # 3. Start Routine (30 pts)
    # Requires a visual stimulus at -0.7 and a mouse component in the same routine
    if result.get("has_start_routine"):
        score += 30
        feedback_parts.append("Start routine correctly configured")
    else:
        feedback_parts.append("Start routine missing or malformed (must have button at y=-0.7)")

    # 4. Continuous Recording (50 pts) - CRITICAL
    if result.get("mouse_save_every_frame"):
        score += 50
        feedback_parts.append("Continuous mouse recording enabled")
    else:
        state = result.get("mouse_save_state", "unknown")
        feedback_parts.append(f"Continuous recording NOT enabled (found setting: '{state}')")

    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }