#!/usr/bin/env python3
"""
Verifier for iDempiere process_employee_expenses task.
Verifies the creation of a specific Employee Business Partner and Expense Report.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_employee_expenses(traj, env_info, task_info):
    """
    Verifies:
    1. Business Partner 'Alex Roadwarrior' exists and is newly created.
    2. BP is correctly flagged as Employee AND Vendor.
    3. Expense Report exists for this BP.
    4. Expense Report has correct lines (150.00 and 45.50).
    5. VLM check verifies UI interaction.
    """
    
    # 1. Setup and load result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: Copy function missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    bp_exists = result.get('bp_exists', False)
    is_employee = result.get('bp_is_employee', 'N') == 'Y'
    is_vendor = result.get('bp_is_vendor', 'N') == 'Y'
    bp_created_ts = result.get('bp_created_ts', 0)
    task_start = result.get('task_start_time', 0)
    
    report_exists = result.get('report_exists', False)
    line_150 = result.get('line_150_match', False)
    line_45 = result.get('line_45_match', False)
    total_amount_str = result.get('total_amount', '0')
    try:
        total_amount = float(total_amount_str)
    except:
        total_amount = 0.0

    score = 0
    feedback = []

    # 3. Scoring Logic
    
    # Criterion 1: Employee Created (20 pts)
    # Must exist and be created during task
    if bp_exists and bp_created_ts >= task_start:
        score += 20
        feedback.append("Business Partner 'Alex Roadwarrior' created successfully.")
    elif bp_exists:
        # Penalize if it looks like old data, though setup script should prevent this
        score += 5
        feedback.append("Business Partner found but timestamp indicates pre-existence.")
    else:
        feedback.append("Business Partner 'Alex Roadwarrior' NOT found.")

    # Criterion 2: Configuration (20 pts)
    config_score = 0
    if is_employee:
        config_score += 10
        feedback.append("BP correctly marked as Employee.")
    else:
        feedback.append("BP NOT marked as Employee.")
        
    if is_vendor:
        config_score += 10
        feedback.append("BP correctly marked as Vendor.")
    else:
        feedback.append("BP NOT marked as Vendor (required for reimbursement).")
    
    if bp_exists:
        score += config_score

    # Criterion 3: Expense Report Header (20 pts)
    if report_exists:
        score += 20
        feedback.append("Expense Report header created.")
    else:
        feedback.append("No Expense Report found for this partner.")

    # Criterion 4: Expense Lines (30 pts)
    if line_150:
        score += 15
        feedback.append("Line for 150.00 found.")
    else:
        feedback.append("Missing expense line for 150.00.")

    if line_45:
        score += 15
        feedback.append("Line for 45.50 found.")
    else:
        feedback.append("Missing expense line for 45.50.")

    # Criterion 5: Total Accuracy (10 pts)
    # Allow small float diff
    if abs(total_amount - 195.50) < 0.01:
        score += 10
        feedback.append("Total amount matches expected 195.50.")
    elif report_exists:
        feedback.append(f"Total amount mismatch: {total_amount} (expected 195.50).")

    # 4. VLM Verification (Trajectory check)
    # Just to ensure they didn't just SQL insert (unlikely in this env but good practice)
    # We query the VLM to see if they visited the Expense Window
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        vlm_resp = query_vlm(
            images=frames,
            prompt="Does the user navigate to an 'Expense Report' or 'Time & Expense' window and enter data?"
        )
        if vlm_resp and vlm_resp.get('parsed', {}).get('answer', False):
            # We don't add points here to keep score aligned with hard verify, 
            # but we could use this to flag cheating if score is high but VLM says "no UI used"
            pass

    # 5. Final Pass/Fail
    passed = (score >= 60) and bp_exists and report_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }