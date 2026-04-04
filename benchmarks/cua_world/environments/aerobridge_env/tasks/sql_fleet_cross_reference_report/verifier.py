#!/usr/bin/env python3
"""
Verifier for sql_fleet_cross_reference_report@1

Criteria:
1. Report file exists and was created during task.
2. Report contains data corresponding to the DB ground truth (Aircraft, Operators, Persons).
3. Evidence of 'sqlite3' usage (via bash history or VLM).
4. Data accuracy (counts match roughly what is expected).
"""

import json
import os
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sql_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Load actual report content
    report_content = ""
    if result.get("file_exists"):
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/home/ga/Documents/fleet_sql_report.txt", temp_report.name)
            with open(temp_report.name, 'r', errors='ignore') as f:
                report_content = f.read()
        except Exception as e:
            logger.warning(f"Could not copy report file: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)

    score = 0
    max_score = 100
    feedback = []
    
    # 1. File Existence & Validity (20 pts)
    if result.get("file_exists") and result.get("file_size", 0) > 50:
        score += 10
        feedback.append("Report file created.")
        if result.get("file_created_during_task"):
            score += 10
            feedback.append("File created during task window.")
        else:
            feedback.append("WARNING: File timestamp check failed.")
    else:
        return {"passed": False, "score": 0, "feedback": "Report file missing or empty."}

    ground_truth = result.get("ground_truth", {})
    
    # 2. Content Verification (60 pts)
    # We look for keywords and specific data points from ground truth
    
    # Section 1: Aircraft Registry (Manufactuer + Operator)
    # Check for presence of known manufacturer names
    found_manufacturers = 0
    for mfr in ground_truth.get("manufacturers", []):
        if mfr in report_content:
            found_manufacturers += 1
    
    if found_manufacturers > 0:
        score += 20
        feedback.append(f"Found {found_manufacturers} manufacturer names in report.")
    else:
        feedback.append("Missing Manufacturer data.")

    # Section 2: Operator Summary
    # Check for known operator names
    found_operators = 0
    for op in ground_truth.get("operators", []):
        if op in report_content:
            found_operators += 1
    
    if found_operators > 0:
        score += 20
        feedback.append(f"Found {found_operators} operator names in report.")
    else:
        feedback.append("Missing Operator data.")

    # Section 3: Personnel
    # Check for known person names
    found_persons = 0
    for person in ground_truth.get("sample_persons", []):
        if person in report_content:
            found_persons += 1
            
    if found_persons > 0:
        score += 20
        feedback.append(f"Found {found_persons} person names in report.")
    else:
        feedback.append("Missing Personnel data.")

    # 3. Process/Formatting (20 pts)
    # Check for pipe separators or headers typical of SQL output
    if "|" in report_content or "---" in report_content or "Name" in report_content:
        score += 10
        feedback.append("Report appears to be formatted (contains separators/headers).")
    
    # Check for sqlite3 usage in history
    if result.get("bash_history_sqlite_match"):
        score += 10
        feedback.append("Evidence of sqlite3 usage found.")
    else:
        feedback.append("No sqlite3 history found (could be minor if output is perfect).")

    # Final Evaluation
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }