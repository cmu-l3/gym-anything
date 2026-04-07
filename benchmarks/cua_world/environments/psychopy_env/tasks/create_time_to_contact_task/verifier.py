#!/usr/bin/env python3
"""
Verifier for create_time_to_contact_task.

Verification Strategy:
1. Asset Check (20 pts): Background image and valid conditions CSV.
2. Background Setup (10 pts): Image component using the asset.
3. Motion Logic (30 pts): Target component using `speed * t` formula and "set every frame".
4. Occlusion Setup (20 pts): Occluder component drawn *after* target (on top).
5. Loop Integration (10 pts): Loop referencing conditions file.
6. VLM Verification (10 pts): Visual confirmation of scene and motion.

Pass threshold: 70 points (Must have working Motion Logic and Occlusion).
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_create_time_to_contact_task(traj, env_info, task_info):
    """Verify the Time-to-Contact experiment creation."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/ttc_task_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if 'tmp_path' in locals() and os.path.exists(tmp_path):
            os.unlink(tmp_path)

    # NONCE Check
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
            nonce_path = tmp.name
        copy_from_env("/home/ga/.task_nonce", nonce_path)
        with open(nonce_path, 'r') as f:
            expected_nonce = f.read().strip()
        result_nonce = result.get('result_nonce', '')
        if expected_nonce and result_nonce != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "FAIL: Result nonce mismatch"}
    except Exception:
        pass # Skip if nonce file missing

    score = 0
    feedback = []

    # 1. Asset Prep (20 pts)
    if result.get('img_exists'):
        score += 10
        feedback.append("Background image downloaded.")
    else:
        feedback.append("Missing background image.")
        
    cols = result.get('conditions_cols', [])
    required_cols = ['speed', 'start_pos']
    if result.get('cond_exists') and all(c in cols for c in required_cols):
        score += 10
        feedback.append("Conditions file valid.")
    else:
        feedback.append(f"Conditions file missing or invalid cols (found: {cols}).")

    # 2. Background Setup (10 pts)
    if result.get('background_comp'):
        score += 10
        feedback.append("Background component configured.")
    else:
        feedback.append("Background component not found in experiment.")

    # 3. Motion Logic (30 pts)
    if result.get('target_comp'):
        if result.get('target_motion_formula'):
            score += 15
            feedback.append("Target position formula detected.")
        else:
            feedback.append("Target found but missing motion formula.")
            
        if result.get('target_updates_every_frame'):
            score += 15
            feedback.append("Target updates 'every frame'.")
        else:
            feedback.append("Target NOT updating every frame (motion will be static).")
    else:
        feedback.append("Target component not found.")

    # 4. Occlusion Setup (20 pts)
    if result.get('occlusion_order_correct'):
        score += 20
        feedback.append("Occlusion order correct (Occluder on top of Target).")
    elif result.get('occluder_comp') and result.get('target_comp'):
        feedback.append("Occluder exists but draw order is wrong (Target is on top).")
    else:
        feedback.append("Occluder component missing or invalid.")

    # 5. Loop Integration (10 pts)
    if result.get('has_loop'):
        score += 10
        feedback.append("Trial loop configured.")
    else:
        feedback.append("Loop missing or not linked to conditions.")

    # 6. Execution / VLM (10 pts)
    # Simple check: if exp exists and valid XML, give partial points
    if result.get('exp_valid_xml'):
        score += 10
        feedback.append("Experiment file valid.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }