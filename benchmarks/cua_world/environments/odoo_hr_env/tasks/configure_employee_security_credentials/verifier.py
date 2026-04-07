#!/usr/bin/env python3
"""
Verifier for configure_employee_security_credentials task.

This script verifies that:
1. The three specific employees (Anita Oliver, Toni Jimenez, Jeffrey Kelly) have the correct Badge ID and PIN.
2. The records were modified *after* the task started (anti-gaming).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_employee_security_credentials(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    targets = task_info.get('metadata', {}).get('targets', [])
    if not targets:
        return {"passed": False, "score": 0, "feedback": "Task metadata missing target definitions"}

    # Retrieve result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result_data.get("connection_error"):
        return {"passed": False, "score": 0, "feedback": f"Error connecting to Odoo database: {result_data['connection_error']}"}

    task_start_ts = result_data.get("task_start_ts", 0)
    employees_data = result_data.get("employees", {})

    score = 0
    max_score = 100
    feedback = []
    
    # Scoring Breakdown:
    # 30 points per employee (15 for Badge ID, 15 for PIN)
    # 10 points for valid timestamps (global check)
    
    all_timestamps_valid = True
    processed_count = 0

    for target in targets:
        name = target['name']
        expected_barcode = target['expected_barcode']
        expected_pin = target['expected_pin']
        
        emp_data = employees_data.get(name)
        
        if not emp_data:
            feedback.append(f"❌ {name}: Employee record not found.")
            all_timestamps_valid = False
            continue
            
        processed_count += 1
        emp_score = 0
        
        # Check Badge ID
        actual_barcode = emp_data.get('barcode')
        if actual_barcode == expected_barcode:
            emp_score += 15
            feedback.append(f"✅ {name}: Badge ID correct ({expected_barcode}).")
        else:
            feedback.append(f"❌ {name}: Badge ID incorrect (Expected: {expected_barcode}, Got: {actual_barcode}).")
            
        # Check PIN
        actual_pin = emp_data.get('pin')
        if actual_pin == expected_pin:
            emp_score += 15
            feedback.append(f"✅ {name}: PIN Code correct.")
        else:
            feedback.append(f"❌ {name}: PIN Code incorrect (Expected: {expected_pin}, Got: {actual_pin}).")

        # Check Timestamp (Anti-gaming)
        # We allow a small buffer for clock skew, though usually not needed on local docker
        write_ts = emp_data.get('write_ts', 0)
        
        # Check if modified after start (with 5s tolerance for clock skew/setup delay)
        if write_ts < (task_start_ts - 5):
            all_timestamps_valid = False
            feedback.append(f"⚠️ {name}: Record not modified during task session.")
        
        score += emp_score

    # Add timestamp bonus if at least one employee was processed and all processed ones were valid
    if processed_count > 0 and all_timestamps_valid and score > 0:
        score += 10
        feedback.append("✅ Timing: Records modified during task session.")
    elif score > 0:
        feedback.append("⚠️ Timing check failed: Some records were not modified during this session.")

    passed = (score == max_score)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }