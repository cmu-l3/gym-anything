#!/usr/bin/env python3
"""
Verifier for sakila_stored_procedure_debugging task.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_sakila_stored_procedure_debugging(traj, env_info, task_info):
    """
    Verify the stored procedure debugging task.
    
    Scoring Criteria (100 pts total):
    1. Sales Report (20 pts): 
       - Procedure runs successfully (10 pts)
       - Export file exists and has data (10 pts)
    2. Dead Inventory (20 pts):
       - Procedure returns rows (logic fixed) (10 pts)
       - Export file exists and has data (10 pts)
    3. Customer Credit (20 pts):
       - Schema updated (column exists) (5 pts)
       - Procedure runs successfully (5 pts)
       - Data populated in DB (5 pts)
       - Export file exists (5 pts)
    4. Anti-gaming / Execution (40 pts):
       - Files created after task start
       - Exports contain reasonable row counts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/debugging_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}

    score = 0
    feedback = []
    task_start = result.get('task_start', 0)

    # 1. Verify Sales Report
    sales_status = result.get('sales_proc_status', 'fail')
    file_sales = result.get('file_sales', {})
    
    if sales_status == 'pass':
        score += 10
        feedback.append("Fixed sp_report_sales_by_category (GROUP BY error resolved).")
    else:
        feedback.append("sp_report_sales_by_category still fails execution.")

    if file_sales.get('exists') and file_sales.get('lines', 0) > 1 and file_sales.get('mtime', 0) > task_start:
        score += 10
        feedback.append("Sales report exported successfully.")
    else:
        feedback.append("Sales report export missing or empty.")

    # 2. Verify Dead Inventory
    dead_rows = result.get('dead_proc_rows', 0)
    file_dead = result.get('file_dead', {})
    
    # Original broken proc returned 0 rows. Fixed should return ~70-80 rows (inventory not in rental)
    if dead_rows > 0:
        score += 10
        feedback.append(f"Fixed sp_identify_dead_inventory (Logic error resolved, found {dead_rows} items).")
    else:
        feedback.append("sp_identify_dead_inventory still returns 0 rows (Logic error likely persists).")

    if file_dead.get('exists') and file_dead.get('lines', 0) > 1 and file_dead.get('mtime', 0) > task_start:
        score += 10
        feedback.append("Dead inventory exported successfully.")
    else:
        feedback.append("Dead inventory export missing or empty.")

    # 3. Verify Customer Credit
    col_exists = result.get('col_credit_score_exists', 0) > 0
    credit_status = result.get('credit_proc_status', 'fail')
    data_count = result.get('credit_data_populated_count', 0)
    file_credit = result.get('file_credit', {})

    if col_exists:
        score += 10
        feedback.append("Schema updated: 'credit_score' column added.")
    else:
        feedback.append("Schema NOT updated: 'credit_score' column missing.")

    if credit_status == 'pass' and data_count > 0:
        score += 10
        feedback.append(f"Credit procedure runs and populated {data_count} records.")
    else:
        feedback.append("Credit procedure failed or did not populate data.")

    if file_credit.get('exists') and file_credit.get('lines', 0) > 1 and file_credit.get('mtime', 0) > task_start:
        score += 20
        feedback.append("Top credit customers exported successfully.")
    else:
        feedback.append("Top credit export missing or empty.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }