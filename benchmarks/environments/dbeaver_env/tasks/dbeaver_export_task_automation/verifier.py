#!/usr/bin/env python3
"""
Verifier for dbeaver_export_task_automation.
Verifies that:
1. A DBeaver "Database Task" was actually created (anti-gaming check).
2. The output CSV file exists and is correct.
3. The SQL script was saved.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dbeaver_export_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    score = 0
    feedback = []
    
    # 1. Verify Task Configuration (The Core Objective)
    # This distinguishes "Manual Export" (easy) from "Automated Task" (the goal)
    if result.get('task_defined', False):
        score += 35
        feedback.append("DBeaver Task 'WeeklyTopSpenders' defined in configuration.")
        
        if result.get('task_type_export', False):
            score += 10
            feedback.append("Task type correctly set to Data Export.")
        else:
            feedback.append("Task exists but type is incorrect.")
    else:
        feedback.append("FAILED: No DBeaver Task named 'WeeklyTopSpenders' found in configuration. Did you just export manually instead of creating a Task?")

    # 2. Verify CSV Output
    if result.get('csv_exists', False):
        score += 10
        feedback.append("Output CSV exists.")
        
        if result.get('csv_created_during_task', False):
            score += 5
        else:
            feedback.append("Warning: CSV file timestamp is old.")
            
        if result.get('csv_header_valid', False):
            score += 10
            feedback.append("CSV headers appear correct.")
            
        if result.get('top_spender_match', False):
            score += 15
            feedback.append("Data validation passed (Top spender matches).")
        else:
            feedback.append("Data validation failed (Top spender incorrect).")
            
        # Row count check (limit 10)
        row_count = result.get('csv_row_count', 0)
        if 9 <= row_count <= 11:
            score += 5
            feedback.append(f"Row count correct ({row_count}).")
        else:
            feedback.append(f"Row count unexpected: {row_count} (expected 10).")
    else:
        feedback.append("Output CSV file not found.")

    # 3. Verify SQL Script
    if result.get('sql_script_exists', False):
        score += 10
        feedback.append("SQL script file found.")
    else:
        feedback.append("SQL script file not found.")

    passed = score >= 70 and result.get('task_defined', False) and result.get('csv_exists', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }