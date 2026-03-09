#!/usr/bin/env python3
"""
Verifier for Chinook Payroll ETL task.

Criteria:
1. Payroll DB connection created in DBeaver (10 pts)
2. Table 'commissions_2011' exists in payroll.db (20 pts)
3. Columns match requirements (EmployeeId, FullName, TotalCommission) (10 pts)
4. Data accuracy (vs Ground Truth) (45 pts)
   - Checks if correct employees are present
   - Checks if commission values are within tolerance
5. SQL script saved (15 pts)

Pass threshold: 60 points
"""

import json
import logging
import os
import tempfile
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_payroll_etl(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load results
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

    # 1. Connection Check (10 pts)
    if result.get("payroll_connection_found", False):
        score += 10
        feedback.append("Payroll database connection found.")
    else:
        feedback.append("Payroll database connection NOT found in DBeaver config.")

    # 2. Script Check (15 pts)
    if result.get("script_exists", False):
        score += 15
        feedback.append("SQL script file found.")
    else:
        feedback.append("SQL script file missing.")

    # 3. Table Existence (20 pts)
    if result.get("table_exists", False):
        score += 20
        feedback.append("Table 'commissions_2011' created.")
    else:
        feedback.append("Table 'commissions_2011' NOT found in payroll.db.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # 4. Column Validity (10 pts)
    if result.get("columns_valid", False):
        score += 10
        feedback.append("Required columns present.")
    else:
        feedback.append("Missing required columns (EmployeeId, FullName, TotalCommission).")
        # Can't verify data if columns are wrong
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # 5. Data Accuracy (45 pts)
    agent_data = result.get("agent_data", [])
    ground_truth = result.get("ground_truth", [])
    
    # Normalize data for comparison (create dict by EmployeeId)
    # Be robust to casing in keys since SQL isn't always case-sensitive in return
    def normalize_row(row):
        norm = {}
        for k, v in row.items():
            norm[k.lower()] = v
        return norm

    agent_map = {normalize_row(r).get('employeeid'): normalize_row(r) for r in agent_data}
    gt_map = {r['EmployeeId']: r for r in ground_truth}

    employees_matched = 0
    values_correct = 0
    total_employees = len(gt_map)

    if total_employees == 0:
        feedback.append("Error in ground truth calculation (0 employees).")
    else:
        for emp_id, gt_row in gt_map.items():
            if emp_id in agent_map:
                employees_matched += 1
                agent_row = agent_map[emp_id]
                
                # Compare commission value (allow small float tolerance)
                # Agent might have type string or float
                try:
                    agent_val = float(agent_row.get('totalcommission', 0))
                    gt_val = float(gt_row['TotalCommission'])
                    
                    if math.isclose(agent_val, gt_val, abs_tol=0.1):
                        values_correct += 1
                    else:
                        feedback.append(f"Emp {emp_id}: Expected {gt_val}, got {agent_val}")
                except ValueError:
                    feedback.append(f"Emp {emp_id}: Invalid number format")
            else:
                feedback.append(f"Employee {emp_id} missing from results")

        # Scoring Logic for Data
        # 15 pts for having all employees
        if employees_matched == total_employees:
            score += 15
        elif employees_matched > 0:
            score += int(15 * (employees_matched / total_employees))
        
        # 30 pts for correct values
        if values_correct == total_employees:
            score += 30
        elif values_correct > 0:
            score += int(30 * (values_correct / total_employees))
            
        feedback.append(f"Data matches: {values_correct}/{total_employees} records correct.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }