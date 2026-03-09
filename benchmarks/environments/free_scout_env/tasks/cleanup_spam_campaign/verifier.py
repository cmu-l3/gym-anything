#!/usr/bin/env python3
"""
Verifier for cleanup_spam_campaign task.

Requirements:
1. All 5 spam tickets from '@spam-lottery.xyz' must be deleted (moved to trash).
2. The 1 legitimate ticket from '@legit-lotto.com' must NOT be deleted.
3. Collateral damage check: The agent shouldn't empty the entire mailbox.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cleanup_spam_campaign(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    # Extract metrics
    spam_total = int(result.get('spam_total', 0))
    spam_deleted = int(result.get('spam_deleted', 0))
    legit_total = int(result.get('legit_total', 0))
    legit_deleted = int(result.get('legit_deleted', 0))
    other_active = int(result.get('other_active_count', 0))

    score = 0
    feedback_parts = []
    
    # Validation of setup state
    if spam_total == 0 or legit_total == 0:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Setup Failure: Spam or Legit tickets not found in database."
        }

    # CRITERION 1: Spam Deletion (50 points)
    # Must delete ALL spam to get full points here? 
    # Let's scale it, but require 100% for the task pass.
    if spam_deleted == spam_total:
        score += 50
        feedback_parts.append(f"Success: All {spam_deleted}/{spam_total} spam tickets deleted")
    elif spam_deleted > 0:
        partial = int(50 * (spam_deleted / spam_total))
        score += partial
        feedback_parts.append(f"Partial: Deleted {spam_deleted}/{spam_total} spam tickets")
    else:
        feedback_parts.append("Fail: No spam tickets deleted")

    # CRITERION 2: Legit Preservation (50 points)
    # This is a critical constraint. If legit ticket is deleted, massive penalty.
    if legit_deleted == 0:
        score += 50
        feedback_parts.append("Success: Legitimate ticket preserved")
    else:
        # Zero score for this section implies penalty, but we can't give negative points directly in this simple sum.
        # However, passing requires high score.
        feedback_parts.append("CRITICAL FAIL: Legitimate ticket was deleted")

    # CRITERION 3: Anti-Gaming / Sanity Check
    # Ensure database isn't empty (checked via 'other_active' or just logic above)
    if other_active == 0:
        feedback_parts.append("Warning: Mailbox appears completely empty (potential over-deletion)")
        # If legit_deleted is > 0, score is already hurt.
        # If legit_deleted is 0 but other_active is 0, that implies the legit ticket IS the other active one,
        # so this check is redundant if we check legit_deleted strictly.
        # But good for logging.

    # Final Pass Logic
    # Strict pass: Must delete ALL spam AND keep legit ticket.
    # Threshold: 100 points
    
    passed = (spam_deleted == spam_total) and (legit_deleted == 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }