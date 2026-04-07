#!/usr/bin/env python3
"""
Verifier for Process Returned Mail (NPAI) task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_returned_mail(traj, env_info, task_info):
    """
    Verify that the agent updated the 3 target patients with 'NPAI - ' prefix
    while preserving the original address and avoiding collateral damage.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    targets = result.get('targets', [])
    if not targets:
        return {"passed": False, "score": 0, "feedback": "No target data found in verification result."}

    # Scoring logic
    # 3 Targets, 25 points each for correct update (Prefix + Preservation)
    # Actually, let's split: 
    # - 15 pts per target for Prefix
    # - 10 pts per target for Data Preservation
    # Total 75 pts for targets
    # 15 pts for No Collateral Damage
    # 10 pts for UI state (implied by success, or check screenshot existence)

    all_targets_correct = True

    for i, target in enumerate(targets):
        t_score = 0
        guid = target.get('guid', 'unknown')
        has_prefix = target.get('has_prefix', False)
        preserves_data = target.get('preserves_data', False)
        
        # Criterion 1: Has Prefix (15 pts)
        if has_prefix:
            t_score += 15
            score += 15
        else:
            feedback.append(f"Patient {i+1}: Address does NOT start with 'NPAI'.")
            all_targets_correct = False
            
        # Criterion 2: Preserves Data (10 pts)
        if preserves_data:
            t_score += 10
            score += 10
        else:
            if has_prefix:
                feedback.append(f"Patient {i+1}: Original address data lost (overwritten).")
            all_targets_correct = False

        logger.info(f"Target {guid}: Prefix={has_prefix}, Preserved={preserves_data}, Points={t_score}")

    # Criterion 3: Collateral Damage (15 pts)
    collateral_damage = result.get('collateral_damage', False)
    if not collateral_damage:
        score += 15
        feedback.append("No other patients were modified.")
    else:
        feedback.append("Penalty: Other patients in the database were incorrectly modified.")

    # Criterion 4: Evidence exists (10 pts)
    # Check if a screenshot was taken, implying the script ran fully
    if result.get('screenshot_exists', False):
        score += 10
    
    passed = (score >= 75) and all_targets_correct

    # Final feedback formatting
    if passed:
        feedback_str = "Success: All patients updated correctly. " + " ".join(feedback)
    else:
        feedback_str = "Failed: " + " ".join(feedback)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback_str,
        "details": result
    }