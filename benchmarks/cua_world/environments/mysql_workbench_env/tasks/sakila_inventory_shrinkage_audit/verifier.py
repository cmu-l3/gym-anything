#!/usr/bin/env python3
"""
Verifier for sakila_inventory_shrinkage_audit task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sakila_inventory_shrinkage_audit(traj, env_info, task_info):
    """
    Verify the inventory audit task.
    
    Scoring Breakdown (100 pts):
    1. Staging Table Created & Populated (20 pts)
    2. Function Created & Logic Correct (20 pts)
    3. View Created (20 pts)
    4. View Logic Correct (Detects Discrepancies) (30 pts)
    5. CSV Export Exists & Valid (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}

    score = 0
    feedback = []

    # 1. Table Verification
    if result.get('table_exists') == 1:
        rows = result.get('table_rows', 0)
        if rows > 0:
            score += 20
            feedback.append(f"Staging table created with {rows} rows (20/20)")
        else:
            score += 10
            feedback.append("Staging table created but empty (10/20)")
    else:
        feedback.append("Staging table `inventory_audit` not found (0/20)")

    # 2. Function Verification
    if result.get('function_exists') == 1:
        if result.get('function_logic_pass') == "pass":
            score += 20
            feedback.append("Function created and logic verified (20/20)")
        else:
            score += 10
            feedback.append("Function created but failed logic test (returned wrong status) (10/20)")
    else:
        feedback.append("Function `fn_get_shrinkage_status` not found (0/20)")

    # 3. View Existence
    if result.get('view_exists') == 1:
        score += 20
        feedback.append("View `v_store1_shrinkage_report` created (20/20)")
    else:
        feedback.append("View not found (0/20)")

    # 4. View Logic / Discrepancy Detection
    # We check if the view correctly identified the injected discrepancies
    # Film 1: MISSING (Variance +1 or similar, depending on calculation direction. Task says System - Actual)
    #   System=X, Actual=X-1. Variance = X - (X-1) = 1.
    # Film 2: EXTRA (Variance -1)
    view_data = result.get('view_content_check', {})
    
    # Check Film 1 (Should be MISSING)
    f1 = view_data.get('1', {})
    f1_ok = f1.get('status') == 'MISSING' and f1.get('variance') == 1
    
    # Check Film 2 (Should be EXTRA)
    f2 = view_data.get('2', {})
    f2_ok = f2.get('status') == 'EXTRA' and f2.get('variance') == -1
    
    if f1_ok and f2_ok:
        score += 30
        feedback.append("View logic correctly identifies MISSING and EXTRA items (30/30)")
    elif f1_ok or f2_ok:
        score += 15
        feedback.append("View logic partially correct (caught some discrepancies) (15/30)")
    elif result.get('view_exists') == 1:
        feedback.append("View exists but did not return the expected discrepancies (0/30)")
    else:
        feedback.append("View logic not tested (view missing) (0/30)")

    # 5. Export Verification
    if result.get('file_exists') and result.get('file_created_during_task'):
        rows = int(result.get('file_rows', 0))
        if rows > 1: # Header + data
            score += 10
            feedback.append("Valid export file created (10/10)")
        else:
            score += 5
            feedback.append("Export file created but appears empty (5/10)")
    else:
        feedback.append("Export file not created or not updated (0/10)")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }