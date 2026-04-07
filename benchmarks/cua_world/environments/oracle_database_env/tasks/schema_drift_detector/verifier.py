#!/usr/bin/env python3
"""
Verifier for Schema Drift Detector task.
Checks if the agent correctly identified 5 specific schema differences
and populated the SYSTEM.SCHEMA_DRIFT_LOG table.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schema_drift(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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
    
    # 1. Check Table Existence (10 pts)
    db_log = result.get("db_log", {})
    if not db_log.get("table_exists"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Table SYSTEM.SCHEMA_DRIFT_LOG was not created."
        }
    
    score += 10
    feedback.append("Table SYSTEM.SCHEMA_DRIFT_LOG created.")

    # 2. Check Drift Detections
    # We look for keywords in the 'object_name' and 'drift_type' columns
    rows = db_log.get("rows", [])
    
    # Helper to find if an issue was detected
    def check_issue(object_keyword, type_keyword=None):
        for r in rows:
            obj = r.get("object_name", "").upper()
            dtype = r.get("drift_type", "").upper()
            
            # Check object match
            if object_keyword.upper() not in obj:
                continue
                
            # Check type match if specified
            if type_keyword and type_keyword.upper() not in dtype:
                continue
                
            return True
        return False

    # Issue 1: Missing Table REGIONS (15 pts)
    # Expect object: REGIONS, type: MISSING or similar
    if check_issue("REGIONS"):
        score += 15
        feedback.append("Detected missing REGIONS table.")
    else:
        feedback.append("Failed to detect missing REGIONS table.")

    # Issue 2: Extra Table FEATURE_FLAGS (15 pts)
    if check_issue("FEATURE_FLAGS"):
        score += 15
        feedback.append("Detected extra FEATURE_FLAGS table.")
    else:
        feedback.append("Failed to detect extra FEATURE_FLAGS table.")

    # Issue 3: Type Mismatch EMPLOYEES.SALARY (20 pts)
    # Expect object: EMPLOYEES or SALARY, type: TYPE or DATATYPE or PRECISION
    if check_issue("SALARY") and check_issue("EMPLOYEES"):
        # We need to distinguish this from the Nullable check on JOBS.MIN_SALARY
        # Let's look specifically for a row that mentions EMPLOYEES and SALARY
        found_sal = False
        for r in rows:
            obj = r.get("object_name", "").upper()
            if "EMPLOYEES" in obj and "SALARY" in obj:
                found_sal = True
                break
        
        if found_sal:
            score += 20
            feedback.append("Detected EMPLOYEES.SALARY mismatch.")
        else:
            feedback.append("Failed to detect EMPLOYEES.SALARY mismatch.")
    else:
        feedback.append("Failed to detect EMPLOYEES.SALARY mismatch.")

    # Issue 4: Extra Column DEPARTMENTS.COST_CENTER (20 pts)
    if check_issue("COST_CENTER"):
        score += 20
        feedback.append("Detected extra column COST_CENTER.")
    else:
        feedback.append("Failed to detect extra column COST_CENTER.")

    # Issue 5: Nullable Mismatch JOBS.MIN_SALARY (10 pts)
    # Check for JOBS and MIN_SALARY
    found_null = False
    for r in rows:
        obj = r.get("object_name", "").upper()
        if "JOBS" in obj and "MIN_SALARY" in obj:
            found_null = True
            break
            
    if found_null:
        score += 10
        feedback.append("Detected JOBS.MIN_SALARY nullable mismatch.")
    else:
        feedback.append("Failed to detect JOBS.MIN_SALARY mismatch.")

    # 3. Check Report File (10 pts)
    if result.get("report_exists") and result.get("report_valid_time"):
        if result.get("report_size", 0) > 10:
            score += 10
            feedback.append("Report file created successfully.")
        else:
            feedback.append("Report file is empty.")
    else:
        feedback.append("Report file missing or not created during task.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }