#!/usr/bin/env python3
import json
import os
import tempfile
import base64
import numpy as np
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_pharmacokinetic_solver(traj, env_info, task_info):
    """
    Verify the PK Solver Fix task.
    
    Criteria:
    1. Bug 1 (Model - Kel) Fixed: 25 pts
    2. Bug 2 (Sim - Accumulation) Fixed: 25 pts
    3. Bug 3 (AUC - Loop) Fixed: 20 pts
    4. No Regressions (All tests pass): 10 pts
    5. Valid Report Generated (Data correctness): 20 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function missing"}

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
    feedback_parts = []
    
    # --- Criterion 1: Kel Fix (25 pts) ---
    # Primary: Test passed. Secondary: Code check.
    if result.get('kel_test_pass') or result.get('model_code_fixed'):
        score += 25
        feedback_parts.append("Model bug (kel) fixed")
    else:
        feedback_parts.append("Model bug (kel) NOT fixed")

    # --- Criterion 2: Accumulation Fix (25 pts) ---
    if result.get('sim_test_pass') or result.get('sim_code_fixed'):
        score += 25
        feedback_parts.append("Simulation bug (accumulation) fixed")
    else:
        feedback_parts.append("Simulation bug (accumulation) NOT fixed")

    # --- Criterion 3: AUC Fix (20 pts) ---
    if result.get('auc_test_pass') or result.get('auc_code_fixed'):
        score += 20
        feedback_parts.append("Analysis bug (AUC loop) fixed")
    else:
        feedback_parts.append("Analysis bug (AUC loop) NOT fixed")

    # --- Criterion 4: No Regressions (10 pts) ---
    if result.get('pytest_exit_code') == 0:
        score += 10
        feedback_parts.append("All tests passed (No regressions)")
    else:
        feedback_parts.append(f"Some tests failed (Exit code {result.get('pytest_exit_code')})")

    # --- Criterion 5: Report Generation & Correctness (20 pts) ---
    csv_exists = result.get('csv_exists', False)
    csv_valid = result.get('csv_valid', False)
    
    if csv_exists and csv_valid:
        # Check values loosely
        try:
            # We don't have the full CSV content, just head. 
            # But the 'csv_valid' check in shell ensures header exists.
            # We rely on 'sim_test_pass' implying the logic is correct, 
            # and 'csv_exists' implying the agent ran the script.
            
            # Anti-gaming: Check if the csv seems to have data
            # Ideally we would reconstruct the simulation here, but without full Python environment 
            # inside the verifier (depending on where this runs), we trust the unit tests + file existence.
            
            # If unit tests passed, the logic is correct. If file exists, they ran it.
            if result.get('sim_test_pass') and result.get('kel_test_pass'):
                score += 20
                feedback_parts.append("Report generated with correct logic")
            else:
                score += 10 # Report exists but logic might be flawed
                feedback_parts.append("Report generated but underlying logic tests failed")
        except Exception:
            feedback_parts.append("Report verification failed")
    else:
        feedback_parts.append("Report file missing or invalid")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }