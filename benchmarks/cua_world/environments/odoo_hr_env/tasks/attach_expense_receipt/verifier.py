#!/usr/bin/env python3
"""
Verifier for attach_expense_receipt task.

Criteria:
1. Target expense record was found/preserved (20 pts)
2. An attachment exists on the correct record (30 pts)
3. The attachment filename matches the receipt (30 pts)
4. The attachment was created AFTER the task started (anti-gaming) (20 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_attach_expense_receipt(traj, env_info, task_info):
    """
    Verify that the receipt was attached to the specific Odoo expense record.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON from container
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
    feedback_parts = []
    
    # Criterion 1: Target Expense Exists (20 pts)
    # Implicitly checked if we could query attachments for it
    if result.get("target_found", False):
        score += 20
        feedback_parts.append("Target expense record identified")
    else:
        feedback_parts.append("Target expense record could not be found (deleted?)")
        return {"passed": False, "score": 0, "feedback": "Target expense record missing"}

    # Criterion 2: Attachment Present (30 pts)
    count = result.get("attachment_count", 0)
    if count > 0:
        score += 30
        feedback_parts.append(f"Found {count} attachment(s)")
    else:
        feedback_parts.append("No attachments found on the record")

    # Criterion 3: Correct Filename (30 pts)
    if result.get("correct_filename", False):
        score += 30
        feedback_parts.append("Attachment filename matches 'receipt_lunch'")
    elif count > 0:
        names = ", ".join(result.get("attachment_names", []))
        feedback_parts.append(f"Wrong attachment filename(s): {names}")

    # Criterion 4: Timestamp Validity (20 pts)
    # Ensures the file wasn't already there (impossible due to setup) and was added *now*
    if result.get("timestamp_valid", False):
        score += 20
        feedback_parts.append("Attachment created during task session")
    elif result.get("correct_filename", False):
        feedback_parts.append("Attachment creation time mismatch (anti-gaming check failed)")

    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }