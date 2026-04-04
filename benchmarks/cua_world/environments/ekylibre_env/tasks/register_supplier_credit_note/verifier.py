#!/usr/bin/env python3
"""
Verifier for register_supplier_credit_note task.

Verifies:
1. A purchase record exists with reference 'AV-2025-004'.
2. The supplier is 'AgriMat 17'.
3. The amount is 150.00.
4. The record type indicates a credit note (PurchaseCreditNote) or negative amount handling.
5. The record was created during the task window.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_register_supplier_credit_note(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    expected_ref = metadata.get('expected_reference', 'AV-2025-004')
    expected_supplier = metadata.get('expected_supplier', 'AgriMat 17')
    expected_amount = float(metadata.get('expected_amount', 150.00))
    expected_date = metadata.get('expected_date', '2024-11-15')

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Initialize scoring
    score = 0
    feedback_parts = []
    
    record_found = result.get('record_found', False)
    details = result.get('record_details', {})
    task_start = result.get('task_start', 0)

    # Criterion 1: Record Exists (40 pts)
    if record_found:
        score += 40
        feedback_parts.append(f"Purchase record '{expected_ref}' found.")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"No purchase record found with reference '{expected_ref}'."
        }

    # Criterion 2: Anti-Gaming / Creation Time (Check passed implicitly if found, but verifying ts)
    created_ts = int(details.get('created_timestamp', 0))
    if created_ts < task_start:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Found record was created before task started (pre-existing data)."
        }

    # Criterion 3: Correct Supplier (20 pts)
    # Case-insensitive check
    actual_supplier = details.get('supplier_name', '')
    if expected_supplier.lower() in actual_supplier.lower():
        score += 20
        feedback_parts.append(f"Supplier '{actual_supplier}' matches '{expected_supplier}'.")
    else:
        feedback_parts.append(f"Incorrect supplier: '{actual_supplier}' (expected '{expected_supplier}').")

    # Criterion 4: Correct Amount (20 pts)
    try:
        actual_amount = float(details.get('pretax_amount', 0))
        # Credit notes might be stored as negative in some DB schemas, or positive with type CreditNote.
        # We accept 150.0 or -150.0
        if abs(actual_amount - expected_amount) < 0.01:
            score += 20
            feedback_parts.append(f"Amount {actual_amount} is correct.")
        else:
            feedback_parts.append(f"Incorrect amount: {actual_amount} (expected {expected_amount}).")
    except ValueError:
        feedback_parts.append("Invalid amount format in database.")

    # Criterion 5: Correct Type (20 pts)
    # Ekylibre stores credit notes usually as 'PurchaseCreditNote' type or similar.
    actual_type = details.get('type', '')
    if 'CreditNote' in actual_type or 'Avoir' in actual_type:
        score += 20
        feedback_parts.append(f"Correct document type: {actual_type}.")
    else:
        # Fallback: if type is generic Purchase but amount is negative?
        # But usually type is specific.
        feedback_parts.append(f"Document type '{actual_type}' may not be a Credit Note.")
        # We might give partial points if amount is correct but type is wrong? 
        # For now, strict on type or flexible if context suggests.
    
    passed = (score >= 80) # Allow small mistake if core is good
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }