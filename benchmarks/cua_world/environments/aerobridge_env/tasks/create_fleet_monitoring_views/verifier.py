#!/usr/bin/env python3
"""
Verifier for create_fleet_monitoring_views task.

Criteria:
1. View Existence (30 pts): 10 pts per view existing in sqlite_master.
2. View Functionality (24 pts): 8 pts per view if SELECT COUNT(*) > 0.
3. SQL Correctness (21 pts): 7 pts per view if definition uses JOINs (and GROUP BY for aggregator).
4. Artifact Creation (20 pts):
   - 10 pts for SQL file existing & non-empty.
   - 10 pts for Output file existing & non-empty.
5. Anti-gaming (5 pts): Files created after task start.

Pass Threshold: 70/100
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_fleet_monitoring_views(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
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
    feedback_parts = []
    
    views = result.get('views', {})
    files = result.get('files', {})
    task_start = result.get('task_start', 0)

    # --- Check Views (Total 75 pts possible here) ---

    # View 1: v_fleet_overview (Join Aircraft + Company + Manufacturer)
    v1 = views.get('v_fleet_overview', {})
    if v1.get('exists'):
        score += 10
        if v1.get('row_count', -1) > 0:
            score += 8
            feedback_parts.append("v_fleet_overview: Exists and returns data.")
        else:
            feedback_parts.append("v_fleet_overview: Exists but returns 0 rows.")
        
        # Check SQL for Join
        sql = base64.b64decode(v1.get('sql_b64', '')).decode('utf-8', errors='ignore').upper()
        if "JOIN" in sql or ("FROM" in sql and "," in sql.split("FROM")[1].split("WHERE")[0]): # Explicit or Implicit join
            score += 7
        else:
            feedback_parts.append("v_fleet_overview: SQL missing JOIN.")
    else:
        feedback_parts.append("v_fleet_overview: Missing.")

    # View 2: v_operator_fleet_size (Join + Aggregation)
    v2 = views.get('v_operator_fleet_size', {})
    if v2.get('exists'):
        score += 10
        if v2.get('row_count', -1) > 0:
            score += 8
            feedback_parts.append("v_operator_fleet_size: Exists and returns data.")
        else:
             feedback_parts.append("v_operator_fleet_size: Exists but returns 0 rows.")
        
        sql = base64.b64decode(v2.get('sql_b64', '')).decode('utf-8', errors='ignore').upper()
        if ("JOIN" in sql or "," in sql.split("FROM")[1].split("WHERE")[0]) and "GROUP BY" in sql:
            score += 7
        else:
            feedback_parts.append("v_operator_fleet_size: SQL missing JOIN or GROUP BY.")
    else:
        feedback_parts.append("v_operator_fleet_size: Missing.")

    # View 3: v_personnel_directory (Join Person + Company)
    v3 = views.get('v_personnel_directory', {})
    if v3.get('exists'):
        score += 10
        if v3.get('row_count', -1) > 0:
            score += 8
            feedback_parts.append("v_personnel_directory: Exists and returns data.")
        else:
            feedback_parts.append("v_personnel_directory: Exists but returns 0 rows.")
            
        sql = base64.b64decode(v3.get('sql_b64', '')).decode('utf-8', errors='ignore').upper()
        if "JOIN" in sql or ("FROM" in sql and "," in sql.split("FROM")[1].split("WHERE")[0]):
            score += 7
        else:
            feedback_parts.append("v_personnel_directory: SQL missing JOIN.")
    else:
        feedback_parts.append("v_personnel_directory: Missing.")

    # --- Check Files (20 pts) ---
    
    # SQL File
    sql_file = files.get('sql_file', {})
    if sql_file.get('exists'):
        score += 10
        feedback_parts.append("SQL definition file saved.")
    else:
        feedback_parts.append("SQL definition file missing.")

    # Output Data File
    data_file = files.get('data_file', {})
    if data_file.get('exists') and data_file.get('size', 0) > 50: # Arbitrary small size check
        score += 10
        feedback_parts.append("Output data file saved.")
    else:
        feedback_parts.append("Output data file missing or empty.")

    # --- Anti-Gaming (5 pts) ---
    valid_timestamps = True
    if sql_file.get('exists') and sql_file.get('mtime', 0) <= task_start:
        valid_timestamps = False
    if data_file.get('exists') and data_file.get('mtime', 0) <= task_start:
        valid_timestamps = False
    
    if valid_timestamps and (sql_file.get('exists') or data_file.get('exists')):
        score += 5
    elif not valid_timestamps:
        feedback_parts.append("Warning: Files appear to be created before task start.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }