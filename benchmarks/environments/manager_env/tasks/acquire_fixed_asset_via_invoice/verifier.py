#!/usr/bin/env python3
"""
Verifier for acquire_fixed_asset_via_invoice task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_acquire_fixed_asset(traj, env_info, task_info):
    """
    Verifies the fixed asset acquisition task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    state = result.get('manager_state', {})
    
    score = 0
    feedback = []

    # Criterion 1: Fixed Assets Module Enabled (20 pts)
    if state.get('fixed_assets_enabled'):
        score += 20
        feedback.append("Fixed Assets module enabled.")
    else:
        feedback.append("Fixed Assets module NOT enabled.")

    # Criterion 2: Asset 'MacBook Pro' Created (20 pts)
    if state.get('asset_found'):
        score += 20
        feedback.append("Asset 'MacBook Pro' found.")
    else:
        feedback.append("Asset 'MacBook Pro' NOT found.")

    # Criterion 3: Supplier 'TechWorld' Created (10 pts)
    if state.get('supplier_found'):
        score += 10
        feedback.append("Supplier 'TechWorld' found.")
    else:
        feedback.append("Supplier 'TechWorld' NOT found.")

    # Criterion 4: Purchase Invoice Created (20 pts)
    if state.get('invoice_found'):
        score += 20
        feedback.append("Purchase Invoice for TechWorld found.")
    else:
        feedback.append("Purchase Invoice for TechWorld NOT found.")

    # Criterion 5: Invoice Linkage and Accuracy (30 pts)
    if state.get('invoice_found'):
        if state.get('invoice_correct'):
            if state.get('invoice_linkage'):
                score += 30
                feedback.append("Invoice correctly linked to Fixed Asset 'MacBook Pro' with correct amount.")
            else:
                score += 10 # Partial credit for amount but wrong account
                feedback.append("Invoice found but NOT linked to Fixed Asset (wrong account selected?).")
        else:
            feedback.append("Invoice found but amount incorrect.")
    
    # Check if app was running
    if not result.get('app_running') == "true":
        feedback.append("WARNING: Manager app was not running at end of task.")

    passed = (score >= 80) and state.get('invoice_linkage')

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }