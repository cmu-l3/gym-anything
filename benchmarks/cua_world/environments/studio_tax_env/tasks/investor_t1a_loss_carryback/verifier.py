#!/usr/bin/env python3
"""Verifier for investor_t1a_loss_carryback task."""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_investor_t1a_loss_carryback(traj, env_info, task_info):
    """Verify Alex Mercer investor return with T1A loss carryback."""
    score = 0
    feedback = []

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env helper"}

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        
        # Pull payload out of the container gracefully
        copy_from_env("C:/Users/Docker/Desktop/t1a_loss_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # Criterion 1: File properly saved (10 pts)
    file_ok = result.get('file_exists') and result.get('file_size_bytes', 0) > 500
    is_new = result.get('file_is_new')
    
    if file_ok and is_new:
        score += 10
        feedback.append("Return file 'alex_mercer.24t' saved and timestamp valid")
    elif file_ok:
        score += 5
        feedback.append("Return file found, but timestamp invalid")
    else:
        feedback.append("FAIL: Return file not found or too small")

    # Criterion 2: T4 Employment Income (10 pts)
    if result.get('contains_92000'):
        score += 10
        feedback.append("T4 employment income $92,000 found")
    else:
        feedback.append("FAIL: T4 income $92,000 not found")

    # Criterion 3: Carrying Charges - Line 22100 (15 pts)
    if result.get('contains_2200'):
        score += 15
        feedback.append("Carrying charges (Line 22100) $2,200 found")
    else:
        feedback.append("FAIL: Carrying charges $2,200 not found")

    # Criterion 4: Schedule 3 Losses (20 pts)
    sch3_score = 0
    notes = []
    if result.get('contains_12000') and result.get('contains_45000'):
        sch3_score += 10
        notes.append("TechCorp")
    if result.get('contains_15000'):
        sch3_score += 5
        notes.append("Bankrupt Gold")
    if result.get('contains_48000'):
        sch3_score += 5
        notes.append("total gross loss")
    
    score += sch3_score
    if sch3_score > 0:
        feedback.append(f"Schedule 3 data found: {', '.join(notes)}")
    else:
        feedback.append("FAIL: Schedule 3 loss data not found")

    # Criterion 5: T1A Application Year 2021 (20 pts)
    if result.get('contains_18500'):
        score += 20
        feedback.append("T1A carryback to 2021 ($18,500) found")
    else:
        feedback.append("FAIL: T1A carryback to 2021 not found")

    # Criterion 6: T1A Application Year 2022 (15 pts)
    if result.get('contains_5500'):
        score += 15
        feedback.append("T1A carryback to 2022 ($5,500) found")
    else:
        feedback.append("FAIL: T1A carryback to 2022 not found")

    # Criterion 7: VLM Trajectory Verification (10 pts)
    vlm_score = 0
    try:
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = '''Look at these screenshots from a tax preparation software (StudioTax).
Did the agent open the 'T1A Request for Loss Carryback' form OR the 'Schedule 3 Capital Gains' form?
Look for terms like 'T1A', 'Loss Carryback', 'Schedule 3', or 'Capital Gains' in the active form window or tabs.

Reply strictly with JSON:
{"opened_relevant_forms": true/false}
'''
            vlm_res = query_vlm(images=images, prompt=prompt)
            if vlm_res and vlm_res.get('success'):
                if vlm_res.get('parsed', {}).get('opened_relevant_forms'):
                    vlm_score = 10
                    feedback.append("VLM verified T1A/Schedule 3 forms were opened")
                else:
                    feedback.append("VLM did not detect relevant forms being opened")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        feedback.append("VLM verification skipped/failed")
    
    score += vlm_score

    # Constraint check: Agent incorrectly carried back GROSS loss instead of NET loss
    # Form T1A uses 50% inclusion rates exclusively
    gross_error = result.get('contains_37000') or result.get('contains_11000')
    if gross_error:
        score = min(score, 45)  # Auto-fail
        feedback.append("CRITICAL FAIL: Gross losses applied to T1A instead of Net Capital Losses. Score capped at 45.")

    passed = score >= 60 and not gross_error and file_ok
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }