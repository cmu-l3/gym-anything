#!/usr/bin/env python3
"""
Verifier for Pivot/Unpivot Reporting task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pivot_unpivot_reporting(traj, env_info, task_info):
    """
    Verifies the creation of pivot/unpivot views and their export.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    with tempfile.TemporaryDirectory() as tmpdir:
        result_path = os.path.join(tmpdir, "result.json")
        try:
            copy_from_env("/tmp/pivot_task_result.json", result_path)
            with open(result_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []

    # 1. Check Source Tables (5 pts)
    if result.get("source_tables_intact"):
        score += 5
    else:
        feedback.append("Source tables (QUARTERLY_COSTS/ANNUAL_SUMMARY_WIDE) missing or empty.")

    views = result.get("views", {})
    files = result.get("files", {})

    # 2. Verify DEPT_JOB_SALARY_PIVOT (30 pts)
    v1 = views.get("DEPT_JOB_SALARY_PIVOT", {})
    if v1.get("exists"):
        score += 5
        # Check for PIVOT keyword
        if "PIVOT" in v1.get("text", "").upper():
            score += 10
        else:
            feedback.append("DEPT_JOB_SALARY_PIVOT: PIVOT keyword not found in definition.")
        
        # Check columns (Job IDs)
        cols = [c.upper() for c in v1.get("columns", [])]
        required_jobs = ["IT_PROG", "SA_REP", "FI_ACCOUNT", "ST_CLERK", "SH_CLERK", "SA_MAN"]
        matches = sum(1 for job in required_jobs if any(job in c for c in cols))
        if matches >= 5:
            score += 10
        else:
            feedback.append(f"DEPT_JOB_SALARY_PIVOT: Missing job role columns (Found: {matches}/6).")
        
        if v1.get("row_count", 0) > 0:
            score += 5
    else:
        feedback.append("DEPT_JOB_SALARY_PIVOT view not found.")

    # 3. Verify QUARTERLY_SPENDING_PIVOT (20 pts)
    v2 = views.get("QUARTERLY_SPENDING_PIVOT", {})
    if v2.get("exists"):
        score += 5
        if "PIVOT" in v2.get("text", "").upper():
            score += 5
        
        cols = [c.upper() for c in v2.get("columns", [])]
        if any("Q1" in c for c in cols) and any("Q4" in c for c in cols):
            score += 5
        
        if v2.get("row_count", 0) > 0:
            score += 5
    else:
        feedback.append("QUARTERLY_SPENDING_PIVOT view not found.")

    # 4. Verify ANNUAL_COSTS_NORMALIZED (20 pts)
    v3 = views.get("ANNUAL_COSTS_NORMALIZED", {})
    if v3.get("exists"):
        score += 5
        if "UNPIVOT" in v3.get("text", "").upper():
            score += 10
        else:
            feedback.append("ANNUAL_COSTS_NORMALIZED: UNPIVOT keyword not found.")
        
        if v3.get("row_count", 0) >= 10: # Should be roughly Depts * 4 categories
            score += 5
    else:
        feedback.append("ANNUAL_COSTS_NORMALIZED view not found.")

    # 5. Verify Exports (25 pts)
    f1 = files.get("DEPT_JOB_SALARY_PIVOT", {})
    f2 = files.get("QUARTERLY_SPENDING_PIVOT", {})
    f3 = files.get("ANNUAL_COSTS_NORMALIZED", {})

    if f1.get("exists") and f1.get("size") > 50: score += 5
    if f2.get("exists") and f2.get("size") > 50: score += 5
    if f3.get("exists") and f3.get("size") > 50: score += 5
    
    # Check if any file was created/modified during task
    if any(f.get("created_during_task") for f in [f1, f2, f3]):
        score += 10
    else:
        feedback.append("Export files not created/modified during task session.")

    passed = (score >= 55)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback) if feedback else "All checks passed."
    }