#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sales_inactivity_gap_analysis(traj, env_info, task_info):
    """
    Verifies the sales inactivity gap analysis task.
    
    Criteria:
    1. Table-Valued Function exists (15 pts)
    2. Function Logic Correct (Dynamic Test) (30 pts) - CRITICAL
    3. View exists (15 pts)
    4. CSV file exists and has data (20 pts)
    5. CSV content matches expectations (checked via logic proxy) (10 pts)
    6. General execution (ADS used, files created) (10 pts)
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Function Exists
    if result.get("function_exists"):
        score += 15
        feedback.append("Function `Sales.tvf_GetSalesPersonMaxGap` created.")
    else:
        feedback.append("Function `Sales.tvf_GetSalesPersonMaxGap` NOT found.")

    # 2. Logic Test (Dynamic)
    if result.get("logic_test_passed"):
        score += 30
        feedback.append("Function logic verified successfully (calculated correct 8-day gap for test data).")
    else:
        raw = result.get("logic_test_raw", "None")
        feedback.append(f"Function logic check FAILED. Expected gap of 8 days (Jan 1 to Jan 10), got: '{raw}'.")

    # 3. View Exists
    if result.get("view_exists"):
        score += 15
        feedback.append("View `Sales.vw_2013_InactivityReport` created.")
    else:
        feedback.append("View `Sales.vw_2013_InactivityReport` NOT found.")

    # 4. CSV Check
    if result.get("csv_exists"):
        rows = result.get("csv_rows", 0)
        if rows >= 5:
            score += 20
            feedback.append(f"CSV exported with {rows} data rows.")
        elif rows > 0:
            score += 10
            feedback.append(f"CSV exported but has only {rows} rows (expected 5).")
        else:
            feedback.append("CSV file is empty.")
    else:
        feedback.append("CSV export NOT found.")

    # 5. Bonus/General (ADS usage implicit if SQL executed)
    if result.get("function_exists") and result.get("view_exists"):
        score += 10 # Consistency points

    # 6. CSV Accuracy (inferred from Logic Test + CSV existence)
    if result.get("logic_test_passed") and result.get("csv_exists") and result.get("csv_rows", 0) == 5:
        score += 10
        feedback.append("High confidence in CSV accuracy based on logic verification.")

    passed = score >= 70 and result.get("logic_test_passed")

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }