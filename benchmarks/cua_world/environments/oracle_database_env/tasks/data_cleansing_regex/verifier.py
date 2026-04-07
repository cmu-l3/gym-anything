#!/usr/bin/env python3
"""
Verifier for data_cleansing_regex task.
Scoring depends on the integrity and correctness of the CLEAN_EMPLOYEES table.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_data_cleansing_regex(traj, env_info, task_info):
    """
    Verifies that the clean_employees table was created correctly.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Copy result file
    with tempfile.TemporaryDirectory() as tmpdir:
        result_path = os.path.join(tmpdir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", result_path)
            with open(result_path, "r") as f:
                result = json.load(f)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to retrieve validation results: {e}"
            }

    score = 0
    feedback = []
    
    # Check Table Existence (5)
    if result.get("table_exists"):
        score += 5
        feedback.append("Table CLEAN_EMPLOYEES exists (+5).")
    else:
        return {"passed": False, "score": 0, "feedback": "Table CLEAN_EMPLOYEES not found."}

    # Check Columns (10)
    if result.get("columns_correct"):
        score += 10
        feedback.append("Column structure is correct (+10).")
    else:
        feedback.append("Column structure incorrect (check names and types).")

    # Check Rows (5)
    row_count = result.get("row_count", 0)
    if row_count == 45:
        score += 5
        feedback.append("Row count is correct (45) (+5).")
    else:
        feedback.append(f"Row count mismatch: found {row_count}, expected 45.")

    data_val = result.get("data_validation", {})
    
    # Check Phones (12)
    # Allow small tolerance if agent deleted a row instead of fixing, though instructions imply keeping all
    if data_val.get("valid_phones", 0) >= 45:
        score += 12
        feedback.append("All phone numbers standardized (+12).")
    elif data_val.get("valid_phones", 0) >= 40:
        score += 6
        feedback.append("Most phone numbers standardized (+6).")
        
    # Check Emails (12)
    if data_val.get("valid_emails", 0) >= 45:
        score += 12
        feedback.append("All emails standardized (+12).")
    elif data_val.get("valid_emails", 0) >= 40:
        score += 6
    
    # Check Salaries (8)
    if data_val.get("valid_salaries", 0) >= 45:
        score += 8
        feedback.append("All salaries converted to numbers (+8).")
        
    # Check Dates (8)
    if data_val.get("valid_dates", 0) >= 45:
        score += 8
        feedback.append("All dates parsed correctly (+8).")
        
    # Check Names (7)
    if data_val.get("clean_names", 0) >= 45:
        score += 7
        feedback.append("Names cleaned and split (+7).")
        
    # Check Job Titles (8)
    if data_val.get("clean_titles", 0) >= 45:
        score += 8
        feedback.append("Job titles expanded (+8).")
    elif data_val.get("clean_titles", 0) >= 40:
        score += 4
        
    # Check Departments (5)
    # We expect consolidation. 45 rows. Random generation usually makes ~8 raw variants mapping to ~8 standard.
    # If the distinct count is low (<=10), it implies consolidation happened.
    dept_count = data_val.get("standard_depts", 99)
    if dept_count <= 10:
        score += 5
        feedback.append("Departments consolidated (+5).")
    else:
        feedback.append(f"Departments not sufficiently consolidated ({dept_count} distinct found).")
        
    # Check Unique IDs (5)
    if data_val.get("unique_ids", 0) == 45:
        score += 5
        feedback.append("Employee IDs are unique (+5).")
        
    # Spot Checks (10)
    spot = result.get("spot_checks", {})
    spot_score = 0
    if spot.get("id_42"): spot_score += 4
    if spot.get("id_88"): spot_score += 3
    if spot.get("id_99"): spot_score += 3
    score += spot_score
    if spot_score == 10:
        feedback.append("Specific record checks passed (+10).")
    elif spot_score > 0:
        feedback.append(f"Partial specific record checks passed (+{spot_score}).")

    # Check Report (5)
    if result.get("report_file_exists"):
        score += 3
        feedback.append("Report file exists (+3).")
        content = result.get("report_file_content", "").lower()
        if "count" in content or "45" in content:
            score += 2
            feedback.append("Report content valid (+2).")
    
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }