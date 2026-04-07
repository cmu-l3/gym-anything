#!/usr/bin/env python3
"""
Verifier for Configure Project Labor Rates task.

Checks:
1. Alice Johnson has a rate of 125.00
2. Bob Smith has a rate of 85.00
3. Rates were created AFTER the task started (anti-gaming)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_project_labor_rates(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    users_meta = metadata.get('users', [])
    
    # Map login to expected rate for easy lookup
    expected_rates = {u['login']: u['expected_rate'] for u in users_meta}
    
    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic checks
    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Error during data export: {result['error']}"}

    if not result.get('project_found'):
        return {"passed": False, "score": 0, "feedback": "Target project 'DevOps Automation' not found."}

    rates_data = result.get('rates', {})
    task_start_time = result.get('task_start_time', 0)
    
    score = 0
    max_score = 100
    feedback_lines = []
    
    # Check each user
    for login, expected_rate in expected_rates.items():
        user_data = rates_data.get(login)
        
        if not user_data:
            feedback_lines.append(f"❌ No rate configured for {login}.")
            continue
            
        actual_rate = user_data.get('rate')
        created_at = user_data.get('created_at', 0)
        
        # Check rate value
        if abs(actual_rate - expected_rate) < 0.01:
            # Check timestamp (Anti-gaming)
            if created_at > task_start_time:
                score += 40
                feedback_lines.append(f"✅ Rate for {login} set correctly to {expected_rate}.")
            else:
                score += 10 # Partial credit for correct value but suspicious timing
                feedback_lines.append(f"⚠️ Rate for {login} is correct ({expected_rate}) but was created before task start.")
        else:
            feedback_lines.append(f"❌ Rate for {login} is incorrect. Expected {expected_rate}, got {actual_rate}.")

    # Check for extra points (clean execution)
    # If both are correct and cleanly set, give remaining 20 points
    if score == 80:
        score += 20
        feedback_lines.append("✅ All configurations correct.")

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }