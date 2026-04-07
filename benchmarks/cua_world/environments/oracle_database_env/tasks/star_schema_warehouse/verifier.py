#!/usr/bin/env python3
"""
Verifier for star_schema_warehouse task.
"""

import json
import logging
import os
import tempfile
import base64

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_star_schema_warehouse(traj, env_info, task_info):
    """
    Verifies the creation of the star schema warehouse.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    db_state = result.get("db_state", {})
    tables = db_state.get("tables", {})
    sample_data = db_state.get("sample_data", {})
    
    # 1. Verify Tables Existence & Columns (40 pts)
    required_tables = {
        "DIM_DEPARTMENT": ["DEPARTMENT_KEY", "DEPARTMENT_NAME", "CITY", "REGION_NAME"],
        "DIM_JOB": ["JOB_KEY", "SALARY_RANGE", "MIN_SALARY"],
        "DIM_EMPLOYEE": ["EMPLOYEE_KEY", "FULL_NAME", "EMAIL"],
        "DIM_TIME": ["TIME_KEY", "YEAR", "QUARTER", "MONTH_NAME"],
        "FACT_WORKFORCE": ["FACT_KEY", "EMPLOYEE_KEY", "DEPARTMENT_KEY", "SALARY"]
    }
    
    for table, req_cols in required_tables.items():
        t_info = tables.get(table, {})
        if t_info.get("exists"):
            score += 4
            feedback.append(f"{table} exists.")
            
            # Check columns
            actual_cols = [c["name"].upper() for c in t_info.get("columns", [])]
            missing = [rc for rc in req_cols if rc not in actual_cols]
            if not missing:
                score += 4
                feedback.append(f"{table} has required columns.")
            else:
                feedback.append(f"{table} missing columns: {missing}.")
        else:
            feedback.append(f"{table} MISSING.")

    # 2. Verify Row Counts (20 pts)
    min_counts = {
        "DIM_DEPARTMENT": 11,
        "DIM_JOB": 19,
        "DIM_EMPLOYEE": 100,
        "DIM_TIME": 5,
        "FACT_WORKFORCE": 100
    }
    
    for table, min_count in min_counts.items():
        count = tables.get(table, {}).get("row_count", 0)
        if count >= min_count:
            score += 4
            feedback.append(f"{table} has data ({count} rows).")
        else:
            feedback.append(f"{table} insufficient data ({count} < {min_count}).")

    # 3. Verify Constraints (Foreign Keys) (10 pts)
    constraints = db_state.get("constraints", [])
    if len(constraints) >= 4:
        score += 10
        feedback.append(f"FACT_WORKFORCE has {len(constraints)} Foreign Keys (Reference Check).")
    elif len(constraints) > 0:
        score += 5
        feedback.append(f"FACT_WORKFORCE has partial Foreign Keys ({len(constraints)}).")
    else:
        feedback.append("FACT_WORKFORCE missing Foreign Key constraints.")

    # 4. Verify Data Integrity Spot Checks (10 pts)
    # Salary Range Calculation
    if sample_data.get("dim_job", {}).get("valid_calc"):
        score += 3
        feedback.append("DIM_JOB.SALARY_RANGE calculated correctly.")
    
    # Denormalization check
    if sample_data.get("dim_dept_valid_rows", 0) > 0:
        score += 4
        feedback.append("DIM_DEPARTMENT denormalized correctly (City/Region populated).")
        
    # Fact Salary Match
    if sample_data.get("fact_salary_match"):
        score += 3
        feedback.append("FACT_WORKFORCE.SALARY matches source.")

    # 5. Verify Output Files (20 pts)
    # Analysis Report
    if result.get("report_exists") and result.get("report_size", 0) > 100:
        try:
            content = base64.b64decode(result.get("report_content_b64", "")).decode('utf-8', errors='ignore')
            if "Department" in content or "Salary" in content:
                score += 15
                feedback.append("Analytical report exists and looks valid.")
            else:
                score += 5
                feedback.append("Analytical report exists but content unclear.")
        except:
            score += 5
    else:
        feedback.append("Analytical report missing or empty.")
        
    # Counts File
    if result.get("counts_exists"):
        score += 5
        feedback.append("Counts file exists.")

    passed = score >= 55
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }