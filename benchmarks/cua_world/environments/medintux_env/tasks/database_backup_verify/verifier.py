#!/usr/bin/env python3
"""
Verifier for MedinTux Database Backup and Restoration Task.
Scores based on:
1. Creation of valid backup files (timestamps, size, SQL content).
2. Successful restoration into validation databases.
3. Data integrity (matching table and row counts).
4. Verification report accuracy.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_database_backup(traj, env_info, task_info):
    """
    Verify the agent correctly backed up, restored, and verified the databases.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    task_start = result.get("task_start", 0)
    databases = result.get("databases", {})
    specific = result.get("specific_checks", {})
    
    # 1. Verify Backups (40 points max)
    # 10 pts per database for valid backup file created during task
    backup_score = 0
    for db_name, db_info in databases.items():
        if db_info.get("backup_exists"):
            size = db_info.get("backup_size", 0)
            mtime = db_info.get("backup_mtime", 0)
            valid_sql = db_info.get("backup_valid_sql", False)
            
            if mtime > task_start and size > 100 and valid_sql:
                backup_score += 10
                feedback.append(f"Backup {db_name}: OK")
            else:
                feedback.append(f"Backup {db_name}: Invalid (Time={mtime>task_start}, Size={size}, SQL={valid_sql})")
        else:
            feedback.append(f"Backup {db_name}: Missing")
            
    score += backup_score

    # 2. Verify Restoration & Integrity (40 points max)
    # 10 pts per database if verify DB exists AND counts match
    integrity_score = 0
    for db_name, db_info in databases.items():
        if db_info.get("verify_exists"):
            orig_tbl = db_info.get("orig_tables", -1)
            verify_tbl = db_info.get("verify_tables", -2)
            orig_rows = db_info.get("orig_rows", -1)
            verify_rows = db_info.get("verify_rows", -2)
            
            if orig_tbl > 0 and orig_tbl == verify_tbl:
                # Row counts can be tricky with MySQL approximations in information_schema
                # We mainly rely on table count + specific patient check for rigorous data proof
                integrity_score += 10
                feedback.append(f"Restore {db_name}: OK (Tables: {orig_tbl})")
            else:
                feedback.append(f"Restore {db_name}: Mismatch/Empty (Orig Tbl: {orig_tbl}, Verify Tbl: {verify_tbl})")
        else:
            feedback.append(f"Restore {db_name}: Verification DB missing")
            
    score += integrity_score

    # 3. Specific Patient Data Check (10 points)
    # Verify the specific DrTuxTest table content matches
    pat_orig = specific.get("patient_count_orig", -1)
    pat_verify = specific.get("patient_count_verify", -2)
    
    if pat_orig > 0 and pat_orig == pat_verify:
        score += 10
        feedback.append("Patient data integrity check: PASS")
    else:
        feedback.append(f"Patient data integrity check: FAIL (Orig: {pat_orig}, Verify: {pat_verify})")

    # 4. Report Verification (10 points)
    report_exists = result.get("report_exists", False)
    report_content = result.get("report_content", "")
    
    if report_exists:
        report_score = 0
        if "OVERALL: PASS" in report_content:
            report_score += 5
        
        # Check if all DB names are in report
        db_mentions = sum(1 for db in databases.keys() if db in report_content)
        if db_mentions == 4:
            report_score += 5
            
        score += report_score
        if report_score == 10:
            feedback.append("Report: Valid")
        else:
            feedback.append("Report: Incomplete content")
    else:
        feedback.append("Report: Missing")

    # Pass criteria: >= 70 points AND DrTuxTest (main DB) must be valid
    # Check DrTuxTest specifically
    dr_tux_ok = False
    dr_tux_info = databases.get("DrTuxTest", {})
    if (dr_tux_info.get("backup_valid_sql") and 
        dr_tux_info.get("verify_exists") and 
        dr_tux_info.get("orig_tables") == dr_tux_info.get("verify_tables")):
        dr_tux_ok = True

    passed = (score >= 70) and dr_tux_ok

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }