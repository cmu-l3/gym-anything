#!/usr/bin/env python3
"""
Verifier for revoke_staff_access task in OpenSIS.

VERIFICATION CRITERIA:
1. Target user (Gerald Fitzpatrick) must still exist in the database (20 pts).
   - Agent should NOT delete the user record.
2. Target user's access must be revoked (60 pts).
   - opensis_access should be 'N' or empty (not 'Y').
3. No collateral damage (20 pts).
   - Verify specific targeting (implicit in finding the specific record).
   - Anti-gaming: State must have changed from Initial 'Y'.

Total: 100 pts.
Pass threshold: 80 pts (Must revoke access AND keep user).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_revoke_staff_access(traj, env_info, task_info):
    """
    Verify that the staff member's access was revoked without deleting the user.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected metadata
    metadata = task_info.get('metadata', {})
    expected_status_revoked = ['N', '', '0', 'false', 'False'] # Acceptable "revoked" values in DB

    # Copy result file from container
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
    
    # Check 1: User Existence (20 pts)
    # The user should NOT be deleted.
    user_exists = result.get('target_user_exists', False)
    if user_exists:
        score += 20
        feedback_parts.append("Staff record preserved (User exists)")
    else:
        feedback_parts.append("CRITICAL: Staff record was deleted! The goal was only to revoke access.")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    # Check 2: Access Revoked (60 pts)
    final_status = result.get('final_access_status', 'UNKNOWN').strip()
    was_modified = result.get('was_modified_during_task', False)

    # In OpenSIS, 'Y' is active. Anything else (usually 'N' or empty) is inactive.
    is_revoked = final_status != 'Y'

    if is_revoked:
        if was_modified:
            score += 60
            feedback_parts.append(f"Access successfully revoked (Status: '{final_status}')")
        else:
            # If status is revoked but wasn't modified during task (e.g. was already N), 
            # that's a setup or logic error, but implies no work done by agent if setup was correct.
            score += 0 
            feedback_parts.append("Access is revoked, but no change detected during task duration.")
    else:
        feedback_parts.append(f"Access is still active (Status: '{final_status}')")

    # Check 3: Collateral/Safety (20 pts)
    # If we got this far (User exists + Access Revoked + Modified), we assume targeted action.
    # We award these points if the main goal is achieved cleanly.
    if user_exists and is_revoked and was_modified:
        score += 20
        feedback_parts.append("Operation performed cleanly")

    # Final Evaluation
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "final_status": final_status,
            "user_exists": user_exists,
            "was_modified": was_modified
        }
    }