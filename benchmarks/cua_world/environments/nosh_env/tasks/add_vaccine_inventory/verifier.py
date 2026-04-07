#!/usr/bin/env python3
import json
import os
import sys
import tempfile
from datetime import datetime

def verify_add_vaccine_inventory(traj, env_info, task_info):
    """
    Verifies that the agent successfully added a specific vaccine lot to the inventory.
    
    Criteria:
    1. Database record exists for Lot 'FL-2026-QA' (Critical)
    2. Expiration date matches '2026-12-31'
    3. Quantity matches 50
    4. CVX/Name corresponds to Influenza (150)
    """
    
    # 1. Setup: Retrieve result data from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Metadata (Expected Values)
    metadata = task_info.get('metadata', {})
    expected_lot = metadata.get('target_lot', 'FL-2026-QA')
    expected_exp = metadata.get('target_expiration', '2026-12-31')
    expected_qty = str(metadata.get('target_quantity', '50'))
    expected_cvx = metadata.get('target_cvx', '150')
    
    # 3. Analyze Results
    score = 0
    feedback_lines = []
    
    data = result.get('data', {})
    record_found = result.get('record_found', False)
    
    # Criterion 1: Record Creation (30 pts)
    if record_found and data.get('lot_number') == expected_lot:
        score += 30
        feedback_lines.append("SUCCESS: Vaccine lot record created in database.")
    else:
        return {"passed": False, "score": 0, "feedback": "FAIL: No inventory record found with the specified Lot Number."}
        
    # Criterion 2: Expiration Date (20 pts)
    # Handle potential date formatting differences (YYYY-MM-DD vs other)
    actual_exp = data.get('expiration_date', '')
    # Simple string match first, assume DB returns YYYY-MM-DD
    if expected_exp in actual_exp:
        score += 20
        feedback_lines.append("SUCCESS: Expiration date is correct.")
    else:
        feedback_lines.append(f"FAIL: Expiration date mismatch. Expected {expected_exp}, found {actual_exp}.")

    # Criterion 3: Quantity (20 pts)
    actual_qty = str(data.get('quantity', '0'))
    # Handle float/int differences (50 vs 50.0)
    if float(actual_qty) == float(expected_qty):
        score += 20
        feedback_lines.append("SUCCESS: Quantity is correct.")
    else:
        feedback_lines.append(f"FAIL: Quantity mismatch. Expected {expected_qty}, found {actual_qty}.")
        
    # Criterion 4: Vaccine Type/CVX (20 pts)
    actual_cvx = str(data.get('cvx_code', ''))
    if expected_cvx in actual_cvx:
        score += 20
        feedback_lines.append("SUCCESS: Vaccine type (CVX) is correct.")
    else:
        feedback_lines.append(f"FAIL: CVX code mismatch. Expected {expected_cvx}, found {actual_cvx}.")
        
    # Criterion 5: App State (10 pts)
    if result.get('app_running', False):
        score += 10
    else:
        feedback_lines.append("WARNING: Browser was closed before verification.")

    # 4. Final Verdict
    # Pass threshold: 60 points (Requires at least record creation + one correct field)
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_lines)
    }