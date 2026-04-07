#!/usr/bin/env python3
"""
Verifier for Workforce Optimization Views task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_workforce_optimization(traj, env_info, task_info):
    """
    Verifies that:
    1. ORG_HIERARCHY_VW exists, has correct columns/data (Hierarchical Query)
    2. SALARY_BAND_ANALYTICS_VW exists, has correct columns/data (Window Functions)
    3. DEPT_JOB_CROSSTAB exists, has correct columns/data (Pivot)
    4. CSV files exist for all three.
    """
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON
    with tempfile.TemporaryDirectory() as tmpdir:
        result_path = os.path.join(tmpdir, "result.json")
        try:
            copy_from_env("/tmp/workforce_optimization_result.json", result_path)
            with open(result_path, "r") as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

    score = 0
    feedback_parts = []
    
    # Check 1: ORG_HIERARCHY_VW (25 pts)
    org = result.get("org_hierarchy_vw", {})
    if org.get("exists") and org.get("valid"):
        score += 8
        
        # Check columns
        req_cols = {"EMPLOYEE_ID", "FULL_NAME", "JOB_ID", "DEPARTMENT_NAME", "MANAGER_NAME", "HIERARCHY_LEVEL", "REPORTING_PATH"}
        found_cols = set(org.get("columns", []))
        if req_cols.issubset(found_cols):
            score += 5
        else:
            feedback_parts.append(f"Org View missing columns: {req_cols - found_cols}")
            
        # Check rows
        if org.get("row_count", 0) >= 100:
            score += 4
        
        # Check Data
        root = org.get("sample_root", {})
        # Level should be 1, path should contain King (or just be King if path is inclusive)
        # Note: sys_connect_by_path usually includes separator at start
        if root.get("level") == 1:
            score += 4
        else:
            feedback_parts.append("Root employee level incorrect")
            
        leaf = org.get("sample_leaf", {})
        path = leaf.get("path", "")
        if "|" in path and "King" in path:
             score += 4
    else:
        feedback_parts.append("ORG_HIERARCHY_VW not valid or missing")

    # Check 2: SALARY_BAND_ANALYTICS_VW (25 pts)
    sal = result.get("salary_analytics_vw", {})
    if sal.get("exists") and sal.get("valid"):
        score += 8
        
        req_cols = {"EMPLOYEE_ID", "FULL_NAME", "DEPARTMENT_NAME", "SALARY", "DEPT_SALARY_RANK", "SALARY_QUARTILE", "DEVIATION_FROM_DEPT_AVG", "PREV_HIRE_SALARY"}
        found_cols = set(sal.get("columns", []))
        if req_cols.issubset(found_cols):
            score += 5
            
        if sal.get("row_count", 0) >= 100:
            score += 4
            
        # Data checks
        data = sal.get("sample_data", {})
        # King is highest paid in Exec dept, so rank should be 1
        if data.get("king_rank") == 1:
            score += 4
        # Deviation should be positive
        if data.get("king_deviation", 0) > 0:
            score += 4
    else:
        feedback_parts.append("SALARY_BAND_ANALYTICS_VW not valid or missing")

    # Check 3: DEPT_JOB_CROSSTAB (20 pts)
    cross = result.get("dept_job_crosstab", {})
    if cross.get("exists"):
        score += 7
        
        req_cols = {"DEPARTMENT_NAME", "IT", "SA", "FI", "TOTAL_HEADCOUNT"} # Checking a subset of critical pivot cols
        found_cols = set(cross.get("columns", []))
        if req_cols.issubset(found_cols):
            score += 5
        
        if cross.get("row_count", 0) >= 11:
            score += 4
            
        if cross.get("sample_it") == 5:
            score += 4
    else:
        feedback_parts.append("DEPT_JOB_CROSSTAB missing")

    # Check 4: CSV Files (30 pts)
    csvs = result.get("csv_files", {})
    
    # Org CSV
    if csvs["org_hierarchy"]["exists"]:
        if csvs["org_hierarchy"]["lines"] >= 100:
            score += 10
        else:
            score += 5 # Partial for existing but small
            feedback_parts.append("Org CSV too small")
            
    # Salary CSV
    if csvs["salary_analytics"]["exists"]:
        if csvs["salary_analytics"]["lines"] >= 100:
            score += 10
        else:
            score += 5
            feedback_parts.append("Salary CSV too small")
            
    # Crosstab CSV
    if csvs["dept_job_matrix"]["exists"]:
        if csvs["dept_job_matrix"]["lines"] >= 5:
            score += 10
        else:
            score += 5
            feedback_parts.append("Matrix CSV too small")

    return {
        "passed": score >= 55,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "All criteria met.",
        "details": result
    }