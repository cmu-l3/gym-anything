#!/usr/bin/env python3
"""
Verifier for Leave Balance System task.

Verification Criteria:
1. Schema Design (30 pts): Tables created with correct columns and constraints.
2. Data Population (25 pts): Policies correct, balances generated for all employees.
3. Business Logic (25 pts): Seniority calculation correct, Executive vs Staff differences.
4. Trigger Enforcement (15 pts): Prevents overdraft, updates balance on approval.
5. Reporting (5 pts): Output file exists and contains valid data.

Pass Threshold: 55 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_leave_balance_system(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    with tempfile.TemporaryDirectory() as tmpdir:
        result_path = os.path.join(tmpdir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", result_path)
            if not os.path.exists(result_path):
                return {"passed": False, "score": 0, "feedback": "Result file not found"}
            with open(result_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    # 1. Schema Design (30 pts)
    tables = result.get("tables_created", {})
    cols = result.get("columns_valid", {})
    constraints = result.get("constraints_valid", {})

    if tables.get("LEAVE_POLICIES") and cols.get("LEAVE_POLICIES"):
        score += 8
        feedback.append("Table LEAVE_POLICIES valid.")
    
    if tables.get("LEAVE_BALANCES") and cols.get("LEAVE_BALANCES"):
        score += 8
        feedback.append("Table LEAVE_BALANCES valid.")
        
    if tables.get("LEAVE_REQUESTS") and cols.get("LEAVE_REQUESTS"):
        score += 6
        feedback.append("Table LEAVE_REQUESTS valid.")

    if constraints.get("LEAVE_BALANCES_FK") and constraints.get("LEAVE_BALANCES_CHECK"):
        score += 8
        feedback.append("Constraints on LEAVE_BALANCES valid.")

    # 2. Data Population (25 pts)
    counts = result.get("data_counts", {})
    
    if counts.get("LEAVE_POLICIES", 0) == 19:
        score += 10
        feedback.append("LEAVE_POLICIES populated correctly (19 rows).")
    elif counts.get("LEAVE_POLICIES", 0) > 0:
        score += 5
        feedback.append("LEAVE_POLICIES has rows but not 19.")

    if counts.get("LEAVE_BALANCES", 0) >= 210: # 107 emp * 2 types = 214
        score += 15
        feedback.append("LEAVE_BALANCES populated correctly (>= 210 rows).")
    elif counts.get("LEAVE_BALANCES", 0) > 0:
        score += 5
        feedback.append("LEAVE_BALANCES has rows but seems incomplete.")

    # 3. Business Logic (25 pts)
    # Policy logic
    if result.get("policy_logic_check"):
        score += 10
        feedback.append("Policy differentiation (Executive vs Staff) correct.")
    
    # Accrual/Seniority logic
    accrual = result.get("accrual_logic_check", {})
    if accrual.get("logic_passed"):
        score += 10
        feedback.append("Seniority accrual logic correct (King > Diana).")
    
    # Procedure existence
    if result.get("procedure_status") == "VALID":
        score += 5
        feedback.append("Procedure CALCULATE_LEAVE_ACCRUALS is valid.")

    # 4. Trigger Enforcement (15 pts)
    if result.get("trigger_status") == "VALID":
        score += 5
        feedback.append("Trigger TRG_LEAVE_BALANCE_CHECK exists and is valid.")
        
        if result.get("trigger_enforcement_test"):
            score += 5
            feedback.append("Trigger correctly blocks overdraft.")
        
        if result.get("trigger_functional_test"):
            score += 5
            feedback.append("Trigger correctly updates balance on approval.")

    # 5. Reporting (5 pts)
    if result.get("report_file_valid"):
        score += 5
        feedback.append("Report file valid and contains data.")

    return {
        "passed": score >= 55,
        "score": score,
        "feedback": " ".join(feedback)
    }