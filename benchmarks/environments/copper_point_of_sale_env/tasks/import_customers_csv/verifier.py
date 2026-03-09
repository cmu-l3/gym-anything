#!/usr/bin/env python3
"""
Verifier for import_customers_csv task.

Checks:
1. Customers exist in database (40 pts)
2. Mapping is correct (Phone/Email in correct fields) (25 pts)
3. Transaction recorded for Sarah Connor (25 pts)
4. Setup/Init (10 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_customers(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    remote_result_path = "C:\\tmp\\task_result.json"
    
    # Temp file for extraction
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Copy from Windows path in container
        # Note: copy_from_env usually handles path conversion or raw string usage
        copy_from_env(remote_result_path, temp_result.name)
        
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
            
    except Exception as e:
        logger.error(f"Failed to copy/read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Verification Logic
    score = 0
    feedback = []
    
    # 1. Setup/Init (10 pts)
    # If we got the JSON, the scripts ran.
    score += 10
    
    # 2. Customers Added (40 pts)
    count = result.get('customers_found_count', 0)
    if count >= 5:
        score += 40
        feedback.append("All 5 customers found in database.")
    elif count > 0:
        partial = int(40 * (count / 5))
        score += partial
        feedback.append(f"Found {count}/5 customers in database.")
    else:
        feedback.append("No imported customers found.")

    # 3. Data Mapping (25 pts)
    if result.get('mapping_correct', False):
        score += 25
        feedback.append("Data mapping correct (Phone/Email).")
    elif result.get('sarah_found', False):
        # Found but mapping wrong?
        feedback.append("Customer found but mapping incorrect (check columns).")
    
    # 4. Transaction Created (25 pts)
    if result.get('transaction_found', False):
        score += 25
        feedback.append("Sale transaction found for Sarah Connor.")
    else:
        feedback.append("No sale transaction found for Sarah Connor.")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }