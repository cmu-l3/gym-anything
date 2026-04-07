#!/usr/bin/env python3
"""
Verifier for Schema Migration Prep task.

Scoring Breakdown (100 pts total):
1. Backup Tables (25 pts)
   - BKP_EMPLOYEES exists & count matches (10 pts)
   - BKP_DEPARTMENTS exists & count matches (8 pts)
   - BKP_JOBS exists & count matches (7 pts)
2. Source Data Integrity (5 pts)
   - Original tables intact
3. DDL Export File (25 pts)
   - Exists & > 2KB (10 pts)
   - Created during task (5 pts)
   - Contains 'CREATE TABLE' SQL (10 pts)
4. Migration Manifest (25 pts)
   - Exists & not empty (10 pts)
   - Lists objects/status (15 pts)
5. Dependency Report (20 pts)
   - Exists & not empty (10 pts)
   - Contains dependency/FK info (10 pts)

Pass Threshold: 60 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schema_migration_prep(traj, env_info, task_info):
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

    # 1. Database Verification
    if not result.get("db_connection_ok"):
        return {"passed": False, "score": 0, "feedback": "Database connection failed during verification."}

    backups = result.get("backup_tables", {})
    sources = result.get("source_tables", {})

    # Check BKP_EMPLOYEES
    bkp_emp = backups.get("BKP_EMPLOYEES", {})
    src_emp = sources.get("EMPLOYEES", {})
    if bkp_emp.get("exists") and bkp_emp.get("count") == src_emp.get("count", -1) and src_emp.get("count", 0) > 0:
        score += 10
        feedback.append("BKP_EMPLOYEES created correctly.")
    else:
        feedback.append("BKP_EMPLOYEES missing or row count mismatch.")

    # Check BKP_DEPARTMENTS
    bkp_dept = backups.get("BKP_DEPARTMENTS", {})
    src_dept = sources.get("DEPARTMENTS", {})
    if bkp_dept.get("exists") and bkp_dept.get("count") == src_dept.get("count", -1):
        score += 8
        feedback.append("BKP_DEPARTMENTS created correctly.")
    else:
        feedback.append("BKP_DEPARTMENTS missing or row count mismatch.")

    # Check BKP_JOBS
    bkp_jobs = backups.get("BKP_JOBS", {})
    src_jobs = sources.get("JOBS", {})
    if bkp_jobs.get("exists") and bkp_jobs.get("count") == src_jobs.get("count", -1):
        score += 7
        feedback.append("BKP_JOBS created correctly.")
    else:
        feedback.append("BKP_JOBS missing or row count mismatch.")

    # Check Source Integrity
    if src_emp.get("exists") and src_dept.get("exists") and src_jobs.get("exists"):
        score += 5
        feedback.append("Source tables intact.")
    else:
        feedback.append("CRITICAL: Source tables modified or dropped!")

    # 2. File Verification
    files = result.get("files", {})

    # DDL File
    ddl = files.get("ddl", {})
    if ddl.get("exists"):
        if ddl.get("size", 0) > 2000:
            score += 10
            feedback.append("DDL file exists and has sufficient size.")
        else:
            score += 5
            feedback.append("DDL file exists but is small.")
            
        if ddl.get("created_during_task"):
            score += 5
            feedback.append("DDL file created during task.")
            
        if "CREATE TABLE" in ddl.get("keywords_found", []):
            score += 10
            feedback.append("DDL file contains CREATE statements.")
    else:
        feedback.append("DDL file missing.")

    # Manifest File
    manifest = files.get("manifest", {})
    if manifest.get("exists") and manifest.get("size", 0) > 100:
        score += 10
        feedback.append("Manifest file exists.")
        if "TABLE" in manifest.get("keywords_found", []):
            score += 15
            feedback.append("Manifest contains object list.")
    else:
        feedback.append("Manifest file missing or empty.")

    # Dependency Report
    deps = files.get("dependencies", {})
    if deps.get("exists") and deps.get("size", 0) > 50:
        score += 10
        feedback.append("Dependency report exists.")
        if "REFERENCES" in deps.get("keywords_found", []):
            score += 10
            feedback.append("Dependency report contains references.")
    else:
        feedback.append("Dependency report missing.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }