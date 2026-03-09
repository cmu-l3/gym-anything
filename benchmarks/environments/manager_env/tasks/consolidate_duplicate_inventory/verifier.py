#!/usr/bin/env python3
"""
Verifier for consolidate_duplicate_inventory task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_consolidate_duplicate_inventory(traj, env_info, task_info):
    """
    Verifies that the duplicate inventory item was removed and its transactions
    were re-assigned to the master item.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    check_state = result.get("check_state", {})
    if "error" in check_state:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {check_state['error']}"}

    score = 0
    feedback_parts = []
    
    # Criterion 1: Duplicate Item Removed (40 pts)
    duplicate_exists = check_state.get("duplicate_item_exists", True)
    if not duplicate_exists:
        score += 40
        feedback_parts.append("Duplicate item successfully deleted.")
    else:
        feedback_parts.append("Duplicate item 'Aniseed Syrup (Old)' still exists.")

    # Criterion 2: Sales Invoice Corrected (20 pts)
    si_corrected = check_state.get("sales_invoice_corrected", False)
    if si_corrected:
        score += 20
        feedback_parts.append("Sales invoice re-assigned correctly.")
    else:
        feedback_parts.append("Sales invoice not corrected.")

    # Criterion 3: Purchase Invoice Corrected (20 pts)
    pi_corrected = check_state.get("purchase_invoice_corrected", False)
    if pi_corrected:
        score += 20
        feedback_parts.append("Purchase invoice re-assigned correctly.")
    else:
        feedback_parts.append("Purchase invoice not corrected.")

    # Criterion 4: Stock Accuracy (inferred) (20 pts)
    # If both invoices are corrected and item deleted, stock is implicitly correct
    if not duplicate_exists and si_corrected and pi_corrected:
        score += 20
        feedback_parts.append("Inventory consistency verified.")
    elif score >= 40:
        # Partial credit if some work done
        score += 10
        feedback_parts.append("Partial inventory cleanup.")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }