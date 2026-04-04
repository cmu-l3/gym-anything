#!/usr/bin/env python3
"""Verifier for reconcile_disconnected_transfers task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reconcile_disconnected_transfers(traj, env_info, task_info):
    """
    Verify that disconnected removal/deposit transactions were replaced by transfers.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: File modified (10 points)
    if result.get("file_modified", False):
        score += 10
        feedback.append("File was saved")
    else:
        feedback.append("File was NOT modified")
        return {"passed": False, "score": 0, "feedback": "File not saved or modified"}

    # Criterion 2: Removals/Deposits Gone (30 points)
    removals = result.get("removals_count", 0)
    deposits = result.get("deposits_count", 0)
    
    if removals == 0 and deposits == 0:
        score += 30
        feedback.append("Old disconnected transactions removed")
    else:
        feedback.append(f"Found {removals} removals and {deposits} deposits remaining (should be 0)")
        if removals < 2: score += 5
        if deposits < 2: score += 5

    # Criterion 3: Transfer 1 Correct ($2500) (30 points)
    if result.get("correct_transfer_1", False):
        score += 30
        feedback.append("Transfer of $2,500.00 created correctly")
    else:
        feedback.append("Transfer of $2,500.00 NOT found or incorrect")

    # Criterion 4: Transfer 2 Correct ($1200) (30 points)
    if result.get("correct_transfer_2", False):
        score += 30
        feedback.append("Transfer of $1,200.00 created correctly")
    else:
        feedback.append("Transfer of $1,200.00 NOT found or incorrect")

    # Pass logic
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }