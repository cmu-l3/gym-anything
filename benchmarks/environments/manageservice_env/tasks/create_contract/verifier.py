#!/usr/bin/env python3
"""
Verifier for create_contract task in ManageEngine ServiceDesk Plus.
Verifies that the agent correctly created a vendor support contract with specific details.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_contract(traj, env_info, task_info):
    """
    Verify the contract creation task.
    
    Scoring Criteria:
    1. Contract exists with correct name (25 pts)
    2. Contract number matches (15 pts)
    3. Vendor is correct (15 pts)
    4. Dates are configured (approximate check due to timestamp formats) (20 pts)
    5. Cost is correct (15 pts)
    6. Anti-gaming: Count increased (10 pts)
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('contract_name', "Cisco SmartNet Support - Core Switches FY2025")
    expected_number = metadata.get('contract_number', "CSC-2025-AMC-00471")
    expected_vendor = metadata.get('vendor_name', "Cisco Systems")
    expected_cost = float(metadata.get('cost', 24750))
    
    score = 0
    feedback = []
    
    # 2. Extract Agent Data
    contract_found = result.get('contract_found', False)
    details = result.get('contract_details', {})
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))
    
    # 3. Verify Criteria
    
    # Criterion 1: Contract Existence & Name (25 pts)
    if contract_found:
        actual_name = details.get('name', '').strip()
        if expected_name.lower() in actual_name.lower():
            score += 25
            feedback.append("Contract found with correct name.")
        else:
            # Partial credit if found but name is slightly off
            score += 10
            feedback.append(f"Contract found but name mismatch. Expected '{expected_name}', got '{actual_name}'.")
    else:
        feedback.append("No matching contract found in database.")
        if current_count > initial_count:
            feedback.append("However, new contracts were created (count increased).")
            score += 5 # Minimal credit for creating *something*
        
        return {
            "passed": False,
            "score": score,
            "feedback": " ".join(feedback)
        }

    # Criterion 2: Contract Number (15 pts)
    actual_number = details.get('number', '').strip()
    if expected_number.lower() in actual_number.lower():
        score += 15
        feedback.append("Contract number matches.")
    else:
        feedback.append(f"Contract number incorrect. Expected '{expected_number}', got '{actual_number}'.")

    # Criterion 3: Vendor Association (15 pts)
    actual_vendor = details.get('vendor_name', '').strip()
    if expected_vendor.lower() in actual_vendor.lower():
        score += 15
        feedback.append("Vendor correctly associated.")
    else:
        feedback.append(f"Vendor incorrect. Expected '{expected_vendor}', got '{actual_vendor}'.")

    # Criterion 4: Dates (20 pts)
    # SDP stores dates as BigInt (milliseconds) often. 
    # We check if they are non-zero/non-null as exact timestamp matching is fragile with timezones.
    start_raw = details.get('start_date_raw', '0')
    end_raw = details.get('end_date_raw', '0')
    
    try:
        # Check if they look like valid timestamps (> year 2000)
        # 946684800000 is approx year 2000 in ms
        s_val = int(start_raw)
        e_val = int(end_raw)
        if s_val > 946684800000 and e_val > 946684800000:
            if e_val > s_val:
                score += 20
                feedback.append("Start and expiry dates are set and valid.")
            else:
                score += 10
                feedback.append("Dates set, but expiry is before start.")
        elif s_val > 0 or e_val > 0:
            score += 10
            feedback.append("One or both dates set, but values may be incorrect.")
        else:
            feedback.append("Dates not set (values are 0/null).")
    except ValueError:
        feedback.append(f"Could not parse dates (raw: {start_raw}, {end_raw}).")

    # Criterion 5: Cost (15 pts)
    try:
        actual_cost = float(details.get('cost', 0))
        # Allow 1.0 tolerance for currency rounding
        if abs(actual_cost - expected_cost) <= 1.0:
            score += 15
            feedback.append("Cost is correct.")
        else:
            feedback.append(f"Cost incorrect. Expected {expected_cost}, got {actual_cost}.")
    except ValueError:
        feedback.append("Invalid cost value format.")

    # Criterion 6: Anti-gaming / New Record (10 pts)
    if current_count > initial_count:
        score += 10
        feedback.append("New contract record confirmed.")
    else:
        feedback.append("Warning: Total contract count did not increase.")

    # 4. Final Result
    passed = score >= 60 and contract_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }