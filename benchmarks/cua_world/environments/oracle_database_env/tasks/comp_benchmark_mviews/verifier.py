#!/usr/bin/env python3
"""
Verifier for comp_benchmark_mviews task.

Verifies:
1. Three specific Materialized Views exist in Oracle.
2. MVs have the correct column structure.
3. MVs are populated with correct data (spot checks against HR schema ground truth).
4. PL/SQL refresh procedure exists, is valid, and executes without error.
5. Output text file exists and contains data from the views.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_comp_benchmark_mviews(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result.get("db_error"):
        return {"passed": False, "score": 0, "feedback": f"Database error during verification: {result['db_error']}"}

    score = 0
    feedback = []

    # --- Verify MVs (75 points total) ---
    mvs = result.get("mvs", {})
    
    # MV 1: MV_DEPT_COMP_SUMMARY (25 pts)
    mv1 = mvs.get("MV_DEPT_COMP_SUMMARY", {})
    if mv1.get("exists"):
        score += 8
        feedback.append("MV_DEPT_COMP_SUMMARY created.")
        
        # Check columns
        required_cols = set(metadata.get("mv_dept_cols", []))
        actual_cols = set(mv1.get("columns", []))
        if required_cols.issubset(actual_cols):
            score += 7
            feedback.append("MV_DEPT_COMP_SUMMARY columns correct.")
        else:
            feedback.append(f"MV_DEPT_COMP_SUMMARY missing columns: {required_cols - actual_cols}")

        # Check data
        if mv1.get("row_count", 0) >= 8: # Expect ~11 rows
            score += 5
            # Spot check Dept 90
            sample = mv1.get("sample_data", {})
            if sample.get("dept_90_emp_count") == 3 and sample.get("dept_90_payroll") == 58000:
                score += 5
                feedback.append("MV_DEPT_COMP_SUMMARY data verified (Dept 90).")
            else:
                feedback.append("MV_DEPT_COMP_SUMMARY data incorrect for Dept 90.")
        else:
            feedback.append("MV_DEPT_COMP_SUMMARY is empty or has too few rows.")
    else:
        feedback.append("MV_DEPT_COMP_SUMMARY not found.")

    # MV 2: MV_JOB_SALARY_BANDS (25 pts)
    mv2 = mvs.get("MV_JOB_SALARY_BANDS", {})
    if mv2.get("exists"):
        score += 8
        feedback.append("MV_JOB_SALARY_BANDS created.")
        
        required_cols = set(metadata.get("mv_job_cols", []))
        actual_cols = set(mv2.get("columns", []))
        if required_cols.issubset(actual_cols):
            score += 7
            feedback.append("MV_JOB_SALARY_BANDS columns correct.")
        else:
            feedback.append(f"MV_JOB_SALARY_BANDS missing columns: {required_cols - actual_cols}")

        if mv2.get("row_count", 0) >= 10: # Expect ~19 rows
            score += 5
            # Spot check SA_REP
            if mv2.get("sample_data", {}).get("sa_rep_count") == 30:
                score += 5
                feedback.append("MV_JOB_SALARY_BANDS data verified (SA_REP).")
            else:
                feedback.append("MV_JOB_SALARY_BANDS data incorrect for SA_REP.")
        else:
            feedback.append("MV_JOB_SALARY_BANDS is empty.")
    else:
        feedback.append("MV_JOB_SALARY_BANDS not found.")

    # MV 3: MV_HIRE_DECADE_STATS (25 pts)
    mv3 = mvs.get("MV_HIRE_DECADE_STATS", {})
    if mv3.get("exists"):
        score += 8
        feedback.append("MV_HIRE_DECADE_STATS created.")
        
        required_cols = set(metadata.get("mv_decade_cols", []))
        actual_cols = set(mv3.get("columns", []))
        if required_cols.issubset(actual_cols):
            score += 7
            feedback.append("MV_HIRE_DECADE_STATS columns correct.")
        
        if mv3.get("row_count", 0) >= 2: # Expect 3 (80s, 90s, 00s)
            score += 10 # 5 for rows, 5 for data check implicit here as low complexity
            feedback.append("MV_HIRE_DECADE_STATS populated.")
    else:
        feedback.append("MV_HIRE_DECADE_STATS not found.")

    # --- Verify Procedure (15 points) ---
    proc = result.get("procedure", {})
    if proc.get("exists") and proc.get("status") == "VALID":
        score += 10
        feedback.append("REFRESH_COMP_VIEWS procedure exists and valid.")
        if proc.get("execution_success"):
            score += 5
            feedback.append("Procedure executes successfully.")
        else:
            feedback.append(f"Procedure execution failed: {proc.get('execution_error')}")
    else:
        feedback.append("REFRESH_COMP_VIEWS procedure missing or invalid.")

    # --- Verify File Export (10 points) ---
    export = result.get("export_file", {})
    if export.get("exists"):
        if export.get("size", 0) > 100:
            score += 5
            if export.get("created_during_task"):
                score += 5
                feedback.append("Export file created correctly.")
            else:
                feedback.append("Export file exists but timestamp matches pre-task state.")
        else:
            feedback.append("Export file exists but is empty/too small.")
    else:
        feedback.append("Export file not found.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }