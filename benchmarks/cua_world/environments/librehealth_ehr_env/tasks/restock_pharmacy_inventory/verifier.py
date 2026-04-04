#!/usr/bin/env python3
"""
Verifier for restock_pharmacy_inventory task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_restock_pharmacy_inventory(traj, env_info, task_info):
    """
    Verifies that the pharmacy inventory was restocked correctly using DB records.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Task Metadata / Expectations
    metadata = task_info.get('metadata', {})
    expected_lot = metadata.get('target_lot', 'SIM-2025-X84')
    expected_qty = int(metadata.get('target_qty', 500))
    expected_exp = metadata.get('target_exp', '2028-12-31')
    expected_vendor = metadata.get('vendor', 'PharmaDistro Inc')

    # Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: Transaction Creation (25 pts)
    if result.get('transaction_found', False):
        score += 25
        feedback_parts.append("Transaction record found.")
    else:
        return {"passed": False, "score": 0, "feedback": "No transaction found with the required Lot Number."}

    # Criterion 2: Lot Number Match (25 pts)
    # Implicitly checked by the SQL query in export_result.sh which searches BY lot number,
    # but we double check the returned value.
    found_lot = result.get('found_lot', '')
    if found_lot == expected_lot:
        score += 25
        feedback_parts.append("Lot Number matches.")
    else:
        feedback_parts.append(f"Lot Number mismatch: Found '{found_lot}', expected '{expected_lot}'.")

    # Criterion 3: Expiration Date Match (20 pts)
    found_exp = result.get('found_exp', '')
    # Handle potentially different date formats if necessary, but usually YYYY-MM-DD
    if found_exp == expected_exp:
        score += 20
        feedback_parts.append("Expiration Date matches.")
    else:
        feedback_parts.append(f"Expiration Date mismatch: Found '{found_exp}', expected '{expected_exp}'.")

    # Criterion 4: Quantity Match (20 pts)
    try:
        found_qty = int(float(result.get('found_qty', 0)))
    except ValueError:
        found_qty = 0
        
    if found_qty == expected_qty:
        score += 20
        feedback_parts.append("Quantity matches.")
    else:
        feedback_parts.append(f"Quantity mismatch: Found {found_qty}, expected {expected_qty}.")

    # Criterion 5: Vendor Check (10 pts)
    # Vendor might be stored as string or ID. If string, we match. If ID, we accept if non-empty.
    found_vendor = result.get('found_vendor', '')
    if expected_vendor.lower() in found_vendor.lower() or (len(found_vendor) > 0 and found_vendor != "0"):
        score += 10
        feedback_parts.append("Vendor info present.")
    else:
        feedback_parts.append("Vendor info missing or incorrect.")

    # Anti-Gaming: Stock Level Check
    # Ensure the master stock level actually increased
    stock_diff = int(result.get('stock_diff', 0))
    if stock_diff >= expected_qty:
        feedback_parts.append("Stock level updated successfully.")
    else:
        # Penalize if stock didn't update (means transaction might be orphaned or not saved correctly)
        score = max(0, score - 20)
        feedback_parts.append(f"WARNING: Master stock level did not increase correctly (Diff: {stock_diff}).")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }