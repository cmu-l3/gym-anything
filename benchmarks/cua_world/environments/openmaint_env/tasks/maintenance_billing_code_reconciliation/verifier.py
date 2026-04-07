#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_maintenance_billing_code_reconciliation(traj, env_info, task_info):
    """
    Verifies that the agent correctly assigned billing codes to work orders.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected data from metadata
    metadata = task_info.get('metadata', {})
    expected_codes = metadata.get('expected_codes', {})
    exception_wo = metadata.get('exception_wo', "WO-BILL-005")

    # Retrieve result from container
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
    feedback = []

    # 1. Verify Mapped and Default Codes (15 pts each for 5 records = 75 pts)
    for wo_code, expected_billing in expected_codes.items():
        wo_data = result.get(wo_code, {})
        
        if not wo_data.get("exists"):
            feedback.append(f"{wo_code}: Record missing/deleted.")
            continue

        actual_billing = wo_data.get("billing_code")
        
        if actual_billing == expected_billing:
            score += 15
            feedback.append(f"{wo_code}: Correct ({actual_billing})")
        else:
            if actual_billing:
                feedback.append(f"{wo_code}: Incorrect (Expected {expected_billing}, got {actual_billing})")
            else:
                feedback.append(f"{wo_code}: No billing code found in Notes")

    # 2. Verify Exception Handling (Warranty) (25 pts)
    # The warranty WO should NOT have a billing code added.
    exception_data = result.get(exception_wo, {})
    if exception_data.get("exists"):
        actual_billing = exception_data.get("billing_code")
        if actual_billing is None:
            # Check if notes were modified at all
            original_notes = "Technician: Vendor Service" # Known from setup
            current_notes = exception_data.get("notes", "")
            
            # Allow minor whitespace diffs, but essentially should be unchanged
            if "BILLING_CODE" not in current_notes:
                score += 25
                feedback.append(f"{exception_wo}: Correctly skipped")
            else:
                feedback.append(f"{exception_wo}: Failed (Modified when should have skipped)")
        else:
             feedback.append(f"{exception_wo}: Failed (Assigned code {actual_billing} but was Warranty)")
    else:
        feedback.append(f"{exception_wo}: Missing/Deleted")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }