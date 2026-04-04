#!/usr/bin/env python3
"""
Verifier for AR Aging Report task.

Scoring (100 points total):
1. File Saved (10 pts): .pbix exists.
2. Data Loaded (10 pts): Inferred from file size (>10KB) and presence of model data.
3. Days Overdue Logic (20 pts): "Days_Overdue" column found in DataModel.
4. Aging Buckets (25 pts): "Aging_Bucket" column and specific bucket strings ("1-30 Days", ">90 Days") found.
5. Matrix Visual (20 pts): Matrix visual type found in Layout.
6. Bar Chart Visual (15 pts): Clustered Bar Chart found in Layout.

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_ar_aging_report(traj, env_info, task_info):
    """
    Verify the Power BI AR Aging Report.
    """
    # 1. Setup access to container result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()

    try:
        copy_from_env("C:/Users/Docker/Desktop/ar_aging_result.json", temp_file.name)
    except Exception as e:
        logger.error(f"Failed to copy result file: {e}")
        return {"passed": False, "score": 0, "feedback": "Could not find result file on desktop. Did you save the report as 'AR_Aging_Report.pbix'?"}

    # 2. Parse Result
    try:
        with open(temp_file.name, 'r', encoding='utf-8-sig', errors='replace') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse verification result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Score Calculation
    score = 0
    feedback_parts = []
    
    # Criterion 1: File Saved (10 pts)
    if result.get('file_exists'):
        score += 10
        feedback_parts.append("File 'AR_Aging_Report.pbix' found.")
    else:
        feedback_parts.append("File 'AR_Aging_Report.pbix' NOT found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}

    # Criterion 2: Data Loaded / File Content (10 pts)
    # A blank PBIX is usually very small (~8KB). With data loaded it should be larger.
    size = result.get('file_size_bytes', 0)
    if size > 15000:
        score += 10
        feedback_parts.append("File size indicates data is loaded.")
    else:
        feedback_parts.append("File size is suspicious (too small). Did you import the CSV?")

    # Context for data model checks
    model_keywords = result.get('model_text_sample', '')
    
    # Criterion 3: Days Overdue Logic (20 pts)
    # We look for the calculated column name "Days_Overdue" in the binary strings
    if "Days_Overdue" in model_keywords:
        score += 20
        feedback_parts.append("'Days_Overdue' calculation found.")
    else:
        feedback_parts.append("'Days_Overdue' column not found in data model.")

    # Criterion 4: Aging Buckets (25 pts)
    # We look for "Aging_Bucket" and specific bucket values
    buckets_found = result.get('buckets_found', False)
    aging_col_found = "Aging_Bucket" in model_keywords
    
    if aging_col_found:
        score += 10
        if buckets_found:
            score += 15
            feedback_parts.append("'Aging_Bucket' column and correct bucket categories found.")
        else:
            feedback_parts.append("'Aging_Bucket' column found but specific categories (e.g., '1-30 Days') missing.")
    else:
        feedback_parts.append("'Aging_Bucket' column not found.")

    # Criterion 5: Matrix Visual (20 pts)
    if result.get('matrix_found', False):
        score += 20
        feedback_parts.append("Matrix visual found.")
    else:
        feedback_parts.append("Matrix visual missing.")

    # Criterion 6: Bar Chart Visual (15 pts)
    if result.get('barchart_found', False):
        score += 15
        feedback_parts.append("Bar chart visual found.")
    else:
        feedback_parts.append("Bar chart visual missing.")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }