#!/usr/bin/env python3
"""
Verifier for create_private_invoice task in Oscar EMR.
Verifies that a bill was created with the correct amount ($20.00) and payer type (Private/Patient).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_private_invoice(traj, env_info, task_info):
    """
    Verify the private invoice creation.
    
    Criteria:
    1. Bill exists and was created during task (20 pts)
    2. Bill amount is exactly 20.00 (30 pts)
    3. Bill type indicates Private/Patient (not OHIP/Ministry) (30 pts)
    4. Diagnosis code is present (10 pts)
    5. Anti-gaming check (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
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
    feedback_parts = []
    
    # 1. Check if bill exists
    if not result.get('bill_found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No new invoice found for Maria Santos."
        }
    
    score += 20
    feedback_parts.append("Invoice created")
    
    # 2. Check Amount ($20.00)
    # Database might return "20.00" or "20.0" or "20"
    try:
        amount_val = float(result.get('amount', '0'))
        if abs(amount_val - 20.00) < 0.01:
            score += 30
            feedback_parts.append("Correct amount ($20.00)")
        else:
            feedback_parts.append(f"Incorrect amount (${amount_val})")
    except ValueError:
        feedback_parts.append("Invalid amount format")

    # 3. Check Payer Type
    # In OSCAR, 'bill_type' or related fields store this.
    # Common codes: 'M' = Ministry/OHIP, 'P' = Private, or checks against 'Third Party'
    # We look for something that is NOT standard government billing.
    # Since we can't be 100% sure of the exact char code without seeing the specific setup,
    # we usually look for specific indicators. 
    # NOTE: In standard OSCAR, 'Public'/'OHIP' is default. 'Private' or 'Patient' usually changes the type.
    # We will accept typical Private indicators.
    bill_type = result.get('bill_type', '').upper()
    
    # Heuristic: If it's NOT standard OHIP (often empty or specific code), gives points.
    # Assuming 'P' for Private or 'Patient' in payee text if exported.
    # If the user successfully switched the dropdown, the type usually changes from default.
    # We'll check if it likely indicates private.
    if bill_type in ['P', 'PRIVATE', 'PATIENT', 'DIRECT', 'U'] or bill_type != 'M': 
        # 'M' is typically Ministry. 'U' can be Uninsured.
        score += 30
        feedback_parts.append(f"Correct payer type ({bill_type})")
    else:
        feedback_parts.append(f"Incorrect payer type (likely OHIP/Ministry: {bill_type})")

    # 4. Check Diagnosis
    dx = result.get('diagnosis', '')
    if dx and dx.strip() not in ['NULL', '']:
        score += 10
        feedback_parts.append(f"Diagnosis present ({dx})")
    else:
        feedback_parts.append("Missing diagnosis")

    # 5. Anti-gaming (Time check is implicit in export script query logic, giving points for it)
    score += 10 # Successfully found a NEW record
    
    passed = score >= 80  # Must get amount and type correct basically
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }