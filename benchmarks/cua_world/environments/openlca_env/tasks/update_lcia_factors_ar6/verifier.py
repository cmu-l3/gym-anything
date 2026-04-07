#!/usr/bin/env python3
"""
Verifier for Update LCIA Factors AR6 task.

Verifies:
1. A new LCIA method 'TRACI 2.1 (IPCC AR6 Modified)' exists in the database.
2. Characterization factors for Methane and Nitrous Oxide match IPCC AR6 values (29.8, 273).
3. A log file describing the update exists.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_update_lcia_factors_ar6(traj, env_info, task_info):
    """Verify that LCIA factors were updated correctly in openLCA."""
    
    # 1. Setup and load result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: Copy function unavailable"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    metadata = task_info.get('metadata', {})
    target_methane = metadata.get('target_methane_value', 29.8)
    target_n2o = metadata.get('target_n2o_value', 273.0)
    tolerance = metadata.get('tolerance', 0.1)

    method_found = result.get('method_found_in_db', False)
    db_methane_str = result.get('db_methane_value', '')
    db_n2o_str = result.get('db_n2o_value', '')
    log_exists = result.get('log_exists', False)

    # 3. Scoring Logic
    score = 0
    feedback = []

    # Criterion 1: Method Created (20 pts)
    if method_found:
        score += 20
        feedback.append("Method 'TRACI 2.1 (IPCC AR6 Modified)' found in database.")
    else:
        feedback.append("Target method NOT found in database.")

    # Criterion 2: Methane Value Correct (35 pts)
    methane_correct = False
    try:
        if db_methane_str and abs(float(db_methane_str) - target_methane) <= tolerance:
            score += 35
            methane_correct = True
            feedback.append(f"Methane factor updated correctly ({db_methane_str}).")
        else:
            feedback.append(f"Methane factor incorrect or missing (Found: '{db_methane_str}', Expected: {target_methane}).")
    except ValueError:
        feedback.append(f"Invalid Methane value format: '{db_methane_str}'")

    # Criterion 3: N2O Value Correct (35 pts)
    n2o_correct = False
    try:
        if db_n2o_str and abs(float(db_n2o_str) - target_n2o) <= tolerance:
            score += 35
            n2o_correct = True
            feedback.append(f"N2O factor updated correctly ({db_n2o_str}).")
        else:
            feedback.append(f"N2O factor incorrect or missing (Found: '{db_n2o_str}', Expected: {target_n2o}).")
    except ValueError:
        feedback.append(f"Invalid N2O value format: '{db_n2o_str}'")

    # Criterion 4: Log File (10 pts)
    if log_exists:
        score += 10
        feedback.append("Log file created.")
    else:
        feedback.append("Log file missing.")

    # Pass Threshold
    # Must have created method and updated BOTH factors to pass
    passed = method_found and methane_correct and n2o_correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "method_found": method_found,
            "methane_val": db_methane_str,
            "n2o_val": db_n2o_str
        }
    }