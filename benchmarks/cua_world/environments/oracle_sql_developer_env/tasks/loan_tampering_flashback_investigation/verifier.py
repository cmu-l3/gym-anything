#!/usr/bin/env python3
"""
Verifier for Loan Tampering Flashback Investigation task.
Uses copy_from_env to safely retrieve task results and secure ground truth data.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_loan_tampering(traj, env_info, task_info):
    """
    Verify the loan tampering investigation task.
    
    Scoring Criteria (100 points max):
    1. INVESTIGATION_FINDINGS table exists and populated (15 pts)
    2. Data Restoration Accuracy (30 pts):
       - Up to 7 loans checked against securely stored ground truth
    3. Flashback Query usage detected (10 pts)
    4. Audit Infrastructure (25 pts):
       - Audit table exists (5 pts)
       - Audit trigger exists (5 pts)
       - Trigger fires correctly on update (15 pts)
    5. CSV Report Exported (10 pts)
    6. GUI Usage / Workflow (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve the execution result JSON
    result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/loan_tampering_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load execution result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Retrieve the hidden Ground Truth JSON
    ground_truth = {}
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/var/lib/task_ground_truth/loan_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load ground truth: {e}")
        # Proceed with empty GT, but restoration score will be 0
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    score = 0
    feedback_parts = []
    
    # Check 1: Findings Table (15 pts)
    findings_exists = result.get('findings_table_exists', False)
    findings_rows = result.get('findings_row_count', 0)
    
    if findings_exists and findings_rows >= 7:
        score += 15
        feedback_parts.append(f"Findings table created & populated ({findings_rows} rows) (15/15)")
    elif findings_exists and findings_rows > 0:
        score += 7
        feedback_parts.append(f"Findings table partially populated ({findings_rows} rows) (7/15)")
    elif findings_exists:
        feedback_parts.append("Findings table exists but is empty (0/15)")
    else:
        feedback_parts.append("Findings table missing (0/15)")

    # Check 2: Data Restoration (30 pts)
    current_loans = result.get('current_loans', {})
    restored_count = 0
    total_loans = len(ground_truth)
    
    for loan_id, gt_data in ground_truth.items():
        curr_data = current_loans.get(str(loan_id), {})
        
        # Check all three critical columns
        match_rate = abs(curr_data.get('interest_rate', 0) - gt_data['interest_rate']) < 0.01
        match_bal = abs(curr_data.get('current_balance', 0) - gt_data['current_balance']) < 0.01
        match_status = str(curr_data.get('status', '')).upper() == str(gt_data['status']).upper()
        
        if match_rate and match_bal and match_status:
            restored_count += 1

    if total_loans > 0:
        restore_score = int((restored_count / total_loans) * 30)
        score += restore_score
        feedback_parts.append(f"Restored {restored_count}/{total_loans} tampered loans ({restore_score}/30)")
    else:
        feedback_parts.append("No ground truth available for restoration check (0/30)")

    # Check 3: Flashback Usage (10 pts)
    flashback_used = result.get('flashback_used', False)
    if flashback_used:
        score += 10
        feedback_parts.append("Flashback queries detected (10/10)")
    else:
        feedback_parts.append("No Flashback queries detected in history (0/10)")

    # Check 4: Audit Infrastructure (25 pts)
    audit_tbl = result.get('audit_table_exists', False)
    audit_trg = result.get('audit_trigger_exists', False)
    audit_fired = result.get('audit_trigger_fired', False)
    
    if audit_tbl:
        score += 5
        feedback_parts.append("Audit table exists (5/5)")
    else:
        feedback_parts.append("Audit table missing (0/5)")
        
    if audit_trg:
        score += 5
        feedback_parts.append("Audit trigger exists (5/5)")
    else:
        feedback_parts.append("Audit trigger missing (0/5)")
        
    if audit_fired:
        score += 15
        feedback_parts.append("Audit trigger fired successfully on update (15/15)")
    else:
        feedback_parts.append("Audit trigger failed to fire on update (0/15)")

    # Check 5: CSV Export (10 pts)
    csv_exists = result.get('csv_exists', False)
    csv_size = result.get('csv_size', 0)
    if csv_exists and csv_size > 50:
        score += 10
        feedback_parts.append("Investigation report CSV exported (10/10)")
    elif csv_exists:
        score += 5
        feedback_parts.append("CSV exported but appears empty/small (5/10)")
    else:
        feedback_parts.append("CSV export missing (0/10)")

    # Check 6: GUI Usage (10 pts)
    gui_evidence = result.get('gui_evidence', {})
    signals = 0
    if gui_evidence.get('mru_connection_count', 0) > 0: signals += 1
    if gui_evidence.get('sqldev_oracle_sessions', 0) > 0: signals += 1
    if gui_evidence.get('sql_history_count', 0) > 0: signals += 1
    if gui_evidence.get('window_title_changed', False): signals += 1
    
    if signals >= 2:
        score += 10
        feedback_parts.append("SQL Developer GUI usage confirmed (10/10)")
    else:
        feedback_parts.append("Minimal/No SQL Developer GUI usage detected (0/10)")

    # Final Evaluation
    # Pass requires a score of 70 AND at least partial restoration AND the trigger firing
    key_criteria_met = (restored_count >= 3) and audit_fired and findings_exists
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }