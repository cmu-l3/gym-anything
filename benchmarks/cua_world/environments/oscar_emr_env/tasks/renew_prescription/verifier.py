#!/usr/bin/env python3
"""
Verifier for Renew Prescription task in OSCAR EMR.
Verifies that a new prescription record was created with the specific
updated parameters (Quantity 90, Repeats 3) while preserving the history.
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_renew_prescription(traj, env_info, task_info):
    """
    Verify renewal of Metformin prescription.
    
    Criteria:
    1. New prescription record exists for the patient (ID > initial).
    2. Drug name contains 'Metformin'.
    3. Quantity is '90'.
    4. Repeats is '3'.
    5. Old prescription record still exists (history preserved).
    6. New prescription is not archived (active).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    max_score = 100
    feedback_parts = []
    
    # Extract data
    new_rx = result.get('new_prescription')
    old_rx_count = result.get('old_prescription_count', 0)
    
    # CRITERION 1: New Record Exists (30 pts)
    if new_rx:
        score += 30
        feedback_parts.append("New prescription record created")
        
        # Check Drug Name (Safety check)
        gn = new_rx.get('gn', '').lower()
        if 'metformin' in gn:
            score += 10
            feedback_parts.append("Correct medication (Metformin)")
        else:
            feedback_parts.append(f"Wrong medication: {gn}")

        # CRITERION 2: Correct Parameters (40 pts)
        # Quantity = 90 (20 pts)
        qty = str(new_rx.get('quantity', ''))
        if '90' in qty:
            score += 20
            feedback_parts.append("Quantity updated to 90")
        else:
            feedback_parts.append(f"Incorrect Quantity: {qty} (Expected 90)")
            
        # Repeats = 3 (20 pts)
        repeats = str(new_rx.get('repeats', ''))
        if repeats == '3':
            score += 20
            feedback_parts.append("Repeats updated to 3")
        else:
            feedback_parts.append(f"Incorrect Repeats: {repeats} (Expected 3)")

        # Check Active Status
        archived = str(new_rx.get('archived', '1'))
        if archived == '0':
            score += 10
            feedback_parts.append("Prescription is active")
        else:
            feedback_parts.append("Warning: New prescription is archived/inactive")
            
    else:
        feedback_parts.append("No new prescription record found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # CRITERION 3: History Preserved (10 pts)
    if old_rx_count > 0:
        score += 10
        feedback_parts.append("Historical record preserved")
    else:
        feedback_parts.append("Warning: Previous prescription record missing (deleted?)")

    # Final Pass/Fail Check
    # Must have created record with at least one correct parameter change to pass
    passed = (score >= 60) and (new_rx is not None)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }