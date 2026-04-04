#!/usr/bin/env python3
"""
Verifier for create_clv_report_calc task.
Verifies the generated ODS file by analyzing a server-side converted CSV version.
"""

import json
import os
import pandas as pd
import logging
import tempfile
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_clv_report_calc(traj, env_info, task_info):
    """
    Verify the Customer Lifetime Value report.
    Criteria:
    1. File exists and created during task.
    2. Contains correct columns (FirstName, LastName, Country, TotalSpent, Segment).
    3. Contains 59 rows (customers).
    4. Sorted by TotalSpent descending.
    5. Segment logic is correct (Gold >= 45, 40 <= Silver < 45, Bronze < 40).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    threshold_gold = metadata.get('threshold_gold', 45.0)
    threshold_silver = metadata.get('threshold_silver', 40.0)

    # Copy result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file CLV_Report.ods not found."}

    if not result_data.get("csv_converted", False):
        return {"passed": False, "score": 10, "feedback": "File exists but could not be verified (conversion failed). Possible empty or corrupt file."}

    # Copy CSV file
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/tmp/CLV_Report_Export.csv", temp_csv.name)
        # Load CSV into Pandas
        try:
            df = pd.read_csv(temp_csv.name)
        except Exception as e:
             return {"passed": False, "score": 15, "feedback": f"File exists but is not valid CSV content: {e}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    score = 0
    feedback = []

    # 1. Check Metadata (File creation) - 10 pts
    if result_data.get("file_created_during_task", False):
        score += 10
        feedback.append("File created during task.")
    else:
        feedback.append("File timestamp indicates it was not created during task.")

    # 2. Check Columns - 10 pts
    # Normalize column names to lowercase for comparison
    df.columns = [c.strip() for c in df.columns]
    cols_lower = [c.lower() for c in df.columns]
    
    required_cols = {
        "firstname": "FirstName",
        "lastname": "LastName",
        "country": "Country",
        "totalspent": "TotalSpent",
        "segment": "Segment"
    }
    
    missing_cols = []
    col_map = {} # map normalized to actual
    for req_key, req_name in required_cols.items():
        if req_key in cols_lower:
            col_map[req_key] = df.columns[cols_lower.index(req_key)]
        else:
            missing_cols.append(req_name)

    if not missing_cols:
        score += 10
        feedback.append("All required columns present.")
    else:
        feedback.append(f"Missing columns: {', '.join(missing_cols)}.")
        # If crucial columns missing, we can't verify much else
        if "totalspent" not in col_map or "segment" not in col_map:
            return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # 3. Check Row Count - 10 pts
    # Chinook has 59 customers
    row_count = len(df)
    if row_count == 59:
        score += 10
        feedback.append("Correct customer count (59).")
    else:
        feedback.append(f"Incorrect row count: {row_count} (expected 59).")

    # 4. Data Validation & Sort Order - 30 pts
    # We check if TotalSpent is numeric and sorted
    try:
        # Clean currency symbols if present
        spent_col = col_map["totalspent"]
        if df[spent_col].dtype == object:
            df[spent_col] = df[spent_col].replace(r'[$,]', '', regex=True).astype(float)
        
        # Check sort order
        if df[spent_col].is_monotonic_decreasing:
            score += 10
            feedback.append("Data is sorted descending by spending.")
        else:
            feedback.append("Data is NOT sorted descending.")

        # Check values against ground truth approximation
        # Top spender in Chinook is Helena Holy ~49.62
        max_spent = df[spent_col].max()
        if 49.0 <= max_spent <= 50.0:
            score += 20
            feedback.append("Spending values match expected range.")
        else:
            feedback.append(f"Spending values seem incorrect (Max: {max_spent}).")
            
    except Exception as e:
        feedback.append(f"Error parsing TotalSpent data: {e}")

    # 5. Segmentation Logic - 40 pts
    segment_col = col_map["segment"]
    logic_errors = 0
    
    try:
        for index, row in df.iterrows():
            val = float(row[spent_col])
            seg = str(row[segment_col]).strip().lower()
            
            expected = "bronze"
            if val >= threshold_gold:
                expected = "gold"
            elif val >= threshold_silver:
                expected = "silver"
            
            if seg != expected:
                logic_errors += 1
        
        if logic_errors == 0:
            score += 40
            feedback.append("Segmentation logic is perfect.")
        elif logic_errors <= 5:
            score += 20
            feedback.append(f"Segmentation logic mostly correct ({logic_errors} errors).")
        else:
            feedback.append(f"Segmentation logic failed ({logic_errors} errors).")
            
    except Exception as e:
        feedback.append(f"Error verifying logic: {e}")

    # Final Pass Check
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }