#!/usr/bin/env python3
"""
Verifier for sakila_revenue_correction_audit task.
Checks database state, view creation, and audit file export.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sakila_revenue_correction_audit(traj, env_info, task_info):
    """
    Scoring Criteria:
    1. View Creation (25 pts): View exists and has correct columns.
    2. Anomaly Detection (15 pts): CSV Export contains rows matching corrupted count.
    3. CSV Export (10 pts): File exists and was created during task.
    4. Data Correction (35 pts): Corrupted records updated to correct rental_rate.
    5. Precision Safety (15 pts): Non-corrupted records were NOT modified.
    
    Pass Threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        # Load results from container
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification results: {str(e)}"}

    score = 0
    feedback_parts = []
    
    # 1. View Creation (25 pts)
    view_exists = result.get("view_exists", False)
    view_valid = result.get("view_columns_valid", False)
    
    if view_exists:
        if view_valid:
            score += 25
            feedback_parts.append("View created correctly (+25)")
        else:
            score += 15
            feedback_parts.append("View created but missing columns (+15)")
    else:
        feedback_parts.append("View 'v_audit_underpayments' not found (0)")

    # 2 & 3. CSV Export & Detection (25 pts total)
    csv_exists = result.get("csv_exists", False)
    csv_fresh = result.get("csv_created_during_task", False)
    csv_rows = result.get("csv_rows", 0)
    total_targets = result.get("total_targets", 0)
    
    if csv_exists and csv_fresh:
        score += 10
        feedback_parts.append("CSV exported (+10)")
        
        # Did they capture roughly the right number of rows?
        # Setup creates ~40. Accept a reasonable margin.
        if total_targets > 0 and abs(csv_rows - total_targets) <= 5:
            score += 15
            feedback_parts.append(f"CSV row count correct ({csv_rows}) (+15)")
        elif csv_rows > 0:
            score += 5
            feedback_parts.append(f"CSV row count mismatch (Found {csv_rows}, expected ~{total_targets}) (+5)")
    else:
        feedback_parts.append("CSV export missing or stale (0)")

    # 4. Data Correction (35 pts)
    fixed_count = result.get("fixed_count", 0)
    
    if total_targets > 0:
        if fixed_count == total_targets:
            score += 35
            feedback_parts.append(f"All {fixed_count} corrupted records fixed (+35)")
        elif fixed_count > 0:
            # Partial credit
            partial = int(35 * (fixed_count / total_targets))
            score += partial
            feedback_parts.append(f"Partially fixed ({fixed_count}/{total_targets}) (+{partial})")
        else:
            feedback_parts.append("No corrupted records were fixed (0)")
    else:
        # Fallback if setup failed to target records
        feedback_parts.append("Setup error: No targets defined")

    # 5. Safety (15 pts)
    safety_violations = result.get("safety_violations", 0)
    if safety_violations == 0:
        score += 15
        feedback_parts.append("No regression on valid data (+15)")
    else:
        feedback_parts.append(f"Safety violation: {safety_violations} valid records were modified (0)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }