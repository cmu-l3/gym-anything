#!/usr/bin/env python3
"""
Verifier for Salary Audit Triggers task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_salary_audit_triggers(traj, env_info, task_info):
    """
    Verifies that:
    1. Objects (Sequence, Table, Triggers) exist and are valid.
    2. Audit table has correct columns.
    3. Triggers correctly logged specific DML actions (Salary, Dept, Job changes).
    4. Data state reflects the DML actions (Updates persisted).
    5. Manager deletion was blocked (Trigger logic test).
    6. Audit log file was exported.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/salary_audit_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    score = 0
    feedback = []

    objects = result.get("objects", {})
    audit_data = result.get("audit_log_data", [])
    emp_state = result.get("employee_state", {})
    trigger_test = result.get("trigger_behavior_test", {})
    file_check = result.get("file_check", {})

    # 1. Objects Existence (20 pts)
    # Sequence (5)
    if objects.get("AUDIT_SEQ", {}).get("exists"):
        score += 5
    else:
        feedback.append("Sequence AUDIT_SEQ missing.")

    # Table (5)
    if objects.get("SALARY_AUDIT_LOG", {}).get("exists"):
        score += 5
    else:
        feedback.append("Table SALARY_AUDIT_LOG missing.")

    # Table Structure (8 pts) - check required columns
    required_cols = ["AUDIT_ID", "EMPLOYEE_ID", "CHANGE_TYPE", "OLD_VALUE", "NEW_VALUE", "CHANGE_DATE", "CHANGED_BY"]
    actual_cols = objects.get("SALARY_AUDIT_LOG", {}).get("columns", {}).keys()
    if objects.get("SALARY_AUDIT_LOG", {}).get("exists"):
        missing_cols = [c for c in required_cols if c not in actual_cols]
        if not missing_cols:
            score += 8
        else:
            feedback.append(f"Table missing columns: {missing_cols}")

    # Triggers (10 pts each if VALID)
    trg_audit = objects.get("TRG_SALARY_AUDIT", {})
    if trg_audit.get("exists") and trg_audit.get("status") == "VALID":
        score += 10
    elif trg_audit.get("exists"):
        score += 5
        feedback.append("TRG_SALARY_AUDIT exists but is INVALID.")
    else:
        feedback.append("TRG_SALARY_AUDIT missing.")

    trg_del = objects.get("TRG_PREVENT_MANAGER_DELETE", {})
    if trg_del.get("exists") and trg_del.get("status") == "VALID":
        score += 10
    elif trg_del.get("exists"):
        score += 5
        feedback.append("TRG_PREVENT_MANAGER_DELETE exists but is INVALID.")
    else:
        feedback.append("TRG_PREVENT_MANAGER_DELETE missing.")

    # 2. Audit Data Verification (24 pts)
    # We look for specific entries created by the agent's DML
    
    # Check Salary Change (Emp 200)
    salary_log = next((x for x in audit_data if x['employee_id'] == 200 and x['change_type'] == 'SALARY'), None)
    if salary_log:
        score += 8
        # Loose check on values to handle formatting (4400 vs 4400.0)
        if '4400' in str(salary_log['old_value']) and '5500' in str(salary_log['new_value']):
             pass # Bonus/Quality check implicit
    else:
        feedback.append("Missing audit log for Emp 200 Salary change.")

    # Check Dept Transfer (Emp 105)
    dept_log = next((x for x in audit_data if x['employee_id'] == 105 and x['change_type'] == 'DEPT_TRANSFER'), None)
    if dept_log:
        score += 8
    else:
        feedback.append("Missing audit log for Emp 105 Dept transfer.")

    # Check Job Change (Emp 206)
    job_log = next((x for x in audit_data if x['employee_id'] == 206 and x['change_type'] == 'JOB_CHANGE'), None)
    if job_log:
        score += 8
    else:
        feedback.append("Missing audit log for Emp 206 Job change.")

    # 3. Employee State Verification (15 pts)
    # Did the updates actually commit?
    if emp_state.get("emp_200_salary") == 5500:
        score += 5
    else:
        feedback.append("Emp 200 salary not updated to 5500.")

    if emp_state.get("emp_105_dept") == 90:
        score += 5
    else:
        feedback.append("Emp 105 dept not updated to 90.")
        
    if emp_state.get("emp_206_job") == 'FI_ACCOUNT':
        score += 5
    else:
        feedback.append("Emp 206 job not updated to FI_ACCOUNT.")

    # 4. Delete Trigger Logic Test (8 pts)
    # Did the export script's attempt to delete a manager fail with the correct error?
    if trigger_test.get("delete_manager_blocked"):
        score += 8
    else:
        msg = trigger_test.get("message", "Unknown")
        feedback.append(f"Manager delete trigger failed validation: {msg}")

    # 5. File Export (10 pts)
    if file_check.get("exists") and file_check.get("size", 0) > 100:
        score += 10
        content = file_check.get("content_preview", "")
        if "SALARY" not in content and "JOB_CHANGE" not in content:
             feedback.append("Audit log file content looks incorrect.")
    else:
        feedback.append("Audit log file missing or empty.")

    # Final Pass/Fail
    passed = (score >= 60) and objects.get("TRG_SALARY_AUDIT", {}).get("status") == "VALID"

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback) if feedback else "All checks passed!"
    }