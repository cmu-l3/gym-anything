#!/usr/bin/env python3
"""
Verifier for configure_recurring_invoice task.
Checks if a template invoice was created and linked to a correctly configured recurring schedule.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_recurring_invoice(traj, env_info, task_info):
    """
    Verify the Recurring Invoice configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_amount = metadata.get('expected_amount', 150.00)
    expected_name = metadata.get('expected_recurring_name', "C&W Monthly Maintenance 2025")
    
    # 1. Load result JSON from container
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
    feedback_parts = []
    
    # Data extraction
    invoice = result.get('template_invoice')
    recurring = result.get('recurring_record')

    # --- CRITERION 1: Template Invoice (25 pts) ---
    # Must exist, correct amount, created during task
    invoice_id = None
    if invoice:
        score += 25
        invoice_id = invoice.get('c_invoice_id')
        feedback_parts.append(f"Template invoice created (ID: {invoice.get('documentno')}, Amt: {invoice.get('grandtotal')})")
    else:
        feedback_parts.append("No matching template invoice found (C&W, 150.00)")

    # --- CRITERION 2: Recurring Record Existence (20 pts) ---
    # Must exist with correct name, created during task
    if recurring:
        score += 20
        feedback_parts.append(f"Recurring record '{expected_name}' created")
        
        # --- CRITERION 3: Recurring Configuration (35 pts) ---
        # Type=Invoice (I), Frequency=Monthly (M), MaxRuns=12
        
        # Check Type
        rec_type = recurring.get('recurringtype')
        if rec_type == 'I': # I = Invoice
            score += 10
            feedback_parts.append("Type: Invoice")
        else:
            feedback_parts.append(f"Type mismatch (found {rec_type}, expected Invoice)")

        # Check Frequency
        freq = recurring.get('frequencytype')
        if freq == 'M': # M = Monthly
            score += 15
            feedback_parts.append("Freq: Monthly")
        else:
            feedback_parts.append(f"Freq mismatch (found {freq}, expected Monthly)")

        # Check Runs
        runs = recurring.get('runsmax')
        if runs == 12:
            score += 10
            feedback_parts.append("Runs: 12")
        else:
            feedback_parts.append(f"Runs mismatch (found {runs}, expected 12)")

        # --- CRITERION 4: Linkage (20 pts) ---
        # Recurring record must point to the template invoice we found
        linked_inv_id = recurring.get('c_invoice_id')
        
        if invoice_id and linked_inv_id == invoice_id:
            score += 20
            feedback_parts.append("Linkage: Correctly linked to template invoice")
        elif linked_inv_id:
            feedback_parts.append("Linkage: Linked to WRONG invoice")
        else:
            feedback_parts.append("Linkage: No invoice linked")
            
    else:
        feedback_parts.append(f"Recurring record '{expected_name}' NOT found")

    # Final scoring
    passed = (score >= 60) and (recurring is not None) and (invoice is not None)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }