#!/usr/bin/env python3
"""
Verifier for manage_invoice_sequence task.

CRITERIA:
1. Invoice 412 must be deleted (30 pts)
2. Associated InvoiceLines must be deleted (20 pts)
3. InvoiceId sequence must be reset to 1000 (50 pts)
4. File must be saved (anti-gaming check)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_manage_invoice_sequence(traj, env_info, task_info):
    """
    Verifies that the agent correctly deleted the record and reset the sequence.
    """
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

    score = 0
    feedback_parts = []
    
    # 1. Check for file modification (Prerequisite)
    if not result.get("file_modified", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Database file was not saved. Changes were not persisted."
        }

    # 2. Check Invoice Deletion (30 pts)
    # The shell script sets this to "false" if the INSERT statement is missing (good)
    invoice_exists = result.get("invoice_412_exists")
    if invoice_exists == "false":
        score += 30
        feedback_parts.append("Invoice 412 deleted successfully")
    elif invoice_exists == "true":
        feedback_parts.append("Invoice 412 still exists")
    else:
        feedback_parts.append("Could not verify invoice deletion")

    # 3. Check InvoiceLine Deletion (20 pts)
    lines_deleted = result.get("invoice_lines_deleted")
    if lines_deleted == "true":
        score += 20
        feedback_parts.append("Associated invoice lines deleted")
    elif lines_deleted == "false":
        feedback_parts.append("Associated invoice lines still exist")
    else:
        feedback_parts.append("Could not verify invoice lines")

    # 4. Check Sequence Reset (50 pts)
    if result.get("sequence_is_1000", False):
        score += 50
        feedback_parts.append("Sequence reset to 1000")
    else:
        feedback_parts.append("Sequence NOT reset to 1000")

    # Final verdict
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }