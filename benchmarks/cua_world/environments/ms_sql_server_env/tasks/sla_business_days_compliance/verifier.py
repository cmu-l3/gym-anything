#!/usr/bin/env python3
"""
Verifier for sla_business_days_compliance task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sla_compliance(traj, env_info, task_info):
    """
    Verify the SLA Business Days Compliance task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    # 1. Verify Table (10 pts)
    if result.get('table_exists') and result.get('holiday_count', 0) >= 8:
        score += 10
        feedback.append("Holiday table created and populated.")
    else:
        feedback.append(f"Holiday table missing or incomplete (Count: {result.get('holiday_count')}).")
        
    # 2. Verify Function Existence (15 pts)
    if result.get('func_exists'):
        score += 15
        feedback.append("Function dbo.fn_GetNetWorkingDays exists.")
    else:
        feedback.append("Function dbo.fn_GetNetWorkingDays not found.")
        
    # 3. Verify Function Logic (40 pts total)
    # Weekend logic (20 pts)
    # Expected: 1 (Fri->Mon)
    try:
        weekend_res = int(result.get('test_weekend_res', -1))
        if weekend_res == 1:
            score += 20
            feedback.append("Function handles weekends correctly.")
        else:
            feedback.append(f"Weekend logic failed. Expected 1, got {weekend_res}.")
    except:
        feedback.append("Weekend logic check failed (invalid output).")
        
    # Holiday logic (20 pts)
    # Expected: 1 (Fri->Tue with Mon holiday)
    try:
        holiday_res = int(result.get('test_holiday_res', -1))
        if holiday_res == 1:
            score += 20
            feedback.append("Function handles holidays correctly.")
        else:
            feedback.append(f"Holiday logic failed. Expected 1, got {holiday_res}.")
    except:
        feedback.append("Holiday logic check failed (invalid output).")
        
    # 4. Verify View (15 pts)
    # Needs to exist, have rows, and required columns
    view_cols = str(result.get('view_columns', '')).lower()
    if result.get('view_exists'):
        if "businessdaystaken" in view_cols and result.get('view_row_count', 0) > 0:
            score += 15
            feedback.append("View created successfully with correct columns and data.")
        else:
            score += 5
            feedback.append("View exists but missing columns or data.")
    else:
        feedback.append("View Sales.vw_ShippingSLABreach not found.")
        
    # 5. Verify CSV (Export check, not critical for logic but good for task completion)
    # We won't assign points in the rubric requested in the prompt (Total 100), 
    # but the prompt rubric had CSV as 20pts. Wait, let's align with the prompt's rubric.
    # Prompt Rubric:
    # Table: 10
    # Func Exists: 15
    # Weekend Logic: 20
    # Holiday Logic: 20
    # View Exists: 15
    # CSV: 20
    # Total: 100
    
    if result.get('csv_exists'):
        row_count = result.get('csv_row_count', 0)
        if 90 <= row_count <= 110: # Tolerate slight off-by-one or header issues
            score += 20
            feedback.append(f"CSV exported correctly ({row_count} rows).")
        elif row_count > 0:
            score += 10
            feedback.append(f"CSV exported but row count mismatch ({row_count} rows).")
        else:
            feedback.append("CSV exists but is empty.")
    else:
        feedback.append("CSV file not found.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }