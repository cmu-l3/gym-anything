#!/usr/bin/env python3
"""
Verifier for correct_billing_claim task.

Scoring Criteria:
1. Target record found and modified (timestamp check) - 30 pts
2. Diagnosis code corrected to '250' - 30 pts
3. Status updated to 'B' (Bill) - 30 pts
4. No duplicate bills created (anti-gaming) - 10 pts
"""

import json
import os
import tempfile
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_correct_billing_claim(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
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

    # 2. Extract Data
    target_id = result.get("target_bill_id")
    found_id = result.get("found_bill_id")
    status = result.get("status", "")
    diagnosis = result.get("diagnosis_code", "")
    update_ts = int(result.get("last_update_ts", 0))
    task_start = int(result.get("task_start_ts", 0))
    bill_count = int(result.get("bill_count_for_date", 0))

    feedback = []
    score = 0

    # 3. Verification Logic

    # Check 1: Record Integrity & Modification (30 pts)
    # Did we find the record? Was it updated AFTER task start?
    if found_id and str(found_id) == str(target_id):
        if update_ts > task_start:
            score += 30
            feedback.append("Target billing record modified successfully.")
        else:
            # It exists but wasn't touched? Or system clock skew?
            # If status changed, we might give partial credit, but timestamp is key for "work done"
            # Let's check values to be lenient on timestamp if values are perfect
            if status == 'B' and diagnosis == '250':
                 score += 30
                 feedback.append("Target record matches expected state (timestamp check bypassed).")
            else:
                 feedback.append("Target record found but not modified (timestamp unchanged).")
    else:
        feedback.append("Target billing record deleted or not found.")
        return {"passed": False, "score": 0, "feedback": "Target record lost."}

    # Check 2: Diagnosis Code (30 pts)
    if str(diagnosis) == "250":
        score += 30
        feedback.append("Diagnosis code corrected to 250.")
    else:
        feedback.append(f"Incorrect diagnosis code: {diagnosis} (Expected: 250).")

    # Check 3: Status (30 pts)
    if status == "B":
        score += 30
        feedback.append("Status updated to 'Bill'.")
    elif status == "S":
        score += 10
        feedback.append("Status updated to 'Saved' but not 'Bill' (Partial credit).")
    else:
        feedback.append(f"Incorrect status: {status} (Expected: B).")

    # Check 4: Anti-Gaming / Cleanliness (10 pts)
    # The user should edit the existing bill, not create a new one leaving the old one as Error.
    # bill_count should be 1 (the injected one).
    if bill_count == 1:
        score += 10
        feedback.append("Clean workflow: No duplicate bills created.")
    else:
        feedback.append(f"Multiple bills ({bill_count}) found for this date. Likely created a new bill instead of fixing the rejection.")

    # 4. Final Result
    passed = (score >= 90)  # Requires almost perfection (Code + Status + Edit vs Create)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }