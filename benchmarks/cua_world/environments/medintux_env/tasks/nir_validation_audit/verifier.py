#!/usr/bin/env python3
"""
Verifier for MedinTux NIR Validation Audit task.

Verification Logic:
1. Check if report file exists and was created during task.
2. Verify total patient count matches database.
3. Verify categorization of 8 specific test patients.
4. Verify summary counts match the detailed list.
5. Check database integrity (records not deleted).
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_nir_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Task Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check basic requirements
    if not result_data.get("report_exists"):
        return {"passed": False, "score": 0, "feedback": "Report file /home/ga/nir_audit_report.txt not found."}

    if not result_data.get("report_created_during_task"):
        return {"passed": False, "score": 0, "feedback": "Report file exists but was not created/modified during the task."}

    # 3. Load the Report Content
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/home/ga/nir_audit_report.txt", temp_report.name)
        with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
            report_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read report file: {str(e)}"}
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    score = 0
    feedback = []

    # --- Scoring Criteria ---

    # A. File Structure & Header (10 pts)
    if "NIR VALIDATION AUDIT REPORT" in report_content:
        score += 5
    else:
        feedback.append("Missing header 'NIR VALIDATION AUDIT REPORT'")

    # Extract Total Count
    total_match = re.search(r"Total patients audited:\s*(\d+)", report_content)
    reported_total = int(total_match.group(1)) if total_match else 0
    
    # Ground truth for total count
    actual_total = int(result_data.get("initial_db_count", 0))
    
    if reported_total == actual_total and actual_total > 0:
        score += 10
        feedback.append(f"Correct total patient count: {reported_total}")
    else:
        feedback.append(f"Incorrect total count (Reported: {reported_total}, Actual: {actual_total})")

    # B. Test Patient Categorization (60 pts - 7.5 pts per patient)
    # Define expected categories
    test_cases = {
        "AUBERT": "VALID",
        "BEAUMONT": "VALID",
        "CHEVALIER": "VALID",
        "DUFOUR": "INVALID_FORMAT",
        "FABRE": "INVALID_FORMAT",
        "GARNIER": "INVALID_KEY",
        "HUBERT": "INVALID_KEY",
        "JOUBERT": "MISSING"
    }

    # Helper to find patient category in report
    # We look for the line containing the Name, and check which category header it falls under OR if the category is on the line
    # The format requested is: <CATEGORY> | <Name> ...
    # So we can regex for the line.
    
    patients_correct = 0
    for name, expected_cat in test_cases.items():
        # Regex to find the line: "CATEGORY | ... Name ..."
        # Case insensitive match
        pattern = re.compile(rf"({expected_cat})\s*\|.*{name}", re.IGNORECASE)
        if pattern.search(report_content):
            patients_correct += 1
        else:
            feedback.append(f"Patient {name} not found or categorized incorrectly (Expected: {expected_cat})")
    
    score += (patients_correct * 7.5)

    # C. Summary Counts Consistency (15 pts)
    # Check if summary section numbers roughly match findings
    summary_valid = re.search(r"VALID:\s*(\d+)", report_content)
    summary_format = re.search(r"INVALID_FORMAT:\s*(\d+)", report_content)
    summary_key = re.search(r"INVALID_KEY:\s*(\d+)", report_content)
    summary_missing = re.search(r"MISSING:\s*(\d+)", report_content)

    if summary_valid and summary_format and summary_key and summary_missing:
        s_val = int(summary_valid.group(1))
        s_fmt = int(summary_format.group(1))
        s_key = int(summary_key.group(1))
        s_mis = int(summary_missing.group(1))
        
        sum_total = s_val + s_fmt + s_key + s_mis
        if sum_total == reported_total:
             score += 15
        else:
             feedback.append("Summary counts do not sum to total audited count")
             score += 5 # Partial credit for existence
    else:
        feedback.append("Summary section missing or incomplete")

    # D. Database Integrity (15 pts)
    # Ensure agent didn't delete records
    current_count = int(result_data.get("current_db_count", 0))
    if current_count >= actual_total:
        score += 15
    else:
        feedback.append("Database integrity failure: Patient records were deleted during the task")
        score = 0 # Automatic fail if data loss occurred

    passed = score >= 60 and patients_correct >= 5
    
    return {
        "passed": passed,
        "score": min(100, int(score)),
        "feedback": "; ".join(feedback)
    }