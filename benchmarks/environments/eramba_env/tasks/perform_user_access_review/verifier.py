#!/usr/bin/env python3
"""
Verifier for perform_user_access_review task.

Verification Logic:
1. Check that 'charlie.vendor' has been marked as Revoked (Status != Keep/Pending).
2. Check that 'charlie.vendor' has the comment 'Contract ended'.
3. Check that 'alice.admin' and 'bob.user' are marked as Keep.
4. Verify timestamps to ensure work was done during the task.

Scoring:
- Correct Revocation (Charlie): 40 pts
- Correct Approvals (Alice/Bob): 30 pts
- Justification (Comment): 20 pts
- Interaction Evidence (Timestamps): 10 pts
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_perform_user_access_review(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Parse Data
    items = result.get('review_items', [])
    task_start = int(result.get('task_start', 0))
    
    # Organize items by account name for easy lookup
    item_map = {item['account']: item for item in items}
    
    charlie = item_map.get('charlie.vendor')
    alice = item_map.get('alice.admin')
    bob = item_map.get('bob.user')

    if not charlie or not alice or not bob:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Critical Error: One or more expected accounts missing from database query."
        }

    score = 0
    feedback_parts = []
    
    # -------------------------------------------------------------
    # 1. Check Interaction (Timestamps) - 10 pts
    # -------------------------------------------------------------
    # Check if any item was modified after task start
    interaction_detected = False
    for item in items:
        mod_time = int(item.get('modified', 0))
        if mod_time > task_start:
            interaction_detected = True
            break
            
    if interaction_detected:
        score += 10
        feedback_parts.append("Database records modified during task")
    else:
        feedback_parts.append("No database records modified during task")

    # -------------------------------------------------------------
    # 2. Check Approvals (Alice & Bob) - 30 pts
    # -------------------------------------------------------------
    # In Eramba: NULL=Pending. 
    # We expect them to be processed. usually status 1 or 2.
    # We expect Alice and Bob to have the SAME status (both kept).
    # And that status should likely be '1' (standard for 'OK/Keep'). 
    # But to be robust, we just check they are processed (not NULL) and match each other.
    
    alice_status = str(alice.get('status'))
    bob_status = str(bob.get('status'))
    
    approvals_ok = False
    if alice_status != 'NULL' and bob_status != 'NULL':
        if alice_status == bob_status:
            score += 30
            approvals_ok = True
            feedback_parts.append(f"Alice and Bob approved (Status: {alice_status})")
        else:
            feedback_parts.append("Alice and Bob have different statuses")
    else:
        feedback_parts.append("Alice or Bob status is still Pending (NULL)")

    # -------------------------------------------------------------
    # 3. Check Revocation (Charlie) - 40 pts
    # -------------------------------------------------------------
    charlie_status = str(charlie.get('status'))
    
    revocation_ok = False
    if charlie_status != 'NULL':
        # Must be different from the 'Keep' status used for Alice/Bob if they were processed
        if approvals_ok and charlie_status != alice_status:
            score += 40
            revocation_ok = True
            feedback_parts.append(f"Charlie revoked (Status: {charlie_status}, distinct from Keep)")
        elif not approvals_ok and charlie_status != '1': 
            # Fallback if approvals failed: assume '1' is keep, so anything else is likely revoke
            score += 20 # Partial credit if we can't compare
            feedback_parts.append(f"Charlie processed (Status: {charlie_status})")
        else:
            feedback_parts.append(f"Charlie has same status as approvals ({charlie_status}) - likely Incorrect")
    else:
        feedback_parts.append("Charlie status is still Pending (NULL)")

    # -------------------------------------------------------------
    # 4. Check Justification (Comment) - 20 pts
    # -------------------------------------------------------------
    comment = charlie.get('feedback', '').lower()
    required_text = "contract ended"
    
    if required_text in comment:
        score += 20
        feedback_parts.append(f"Correct comment found ('{comment}')")
    elif comment:
        score += 10 # Partial for any comment
        feedback_parts.append(f"Comment present but missing specific text ('{comment}')")
    else:
        feedback_parts.append("No comment provided for Charlie")

    # Final Pass Check
    # Threshold: 70
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }