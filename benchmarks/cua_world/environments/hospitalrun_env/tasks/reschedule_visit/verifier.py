#!/usr/bin/env python3
"""
Verifier for reschedule_visit task.

Verifies that:
1. The specific visit document (visit_p1_cameron_v1) still exists (was not deleted).
2. The document revision (_rev) has changed (it was modified).
3. The startDate is now October 15, 2026.
4. The reason field contains "Rescheduled per patient request".
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reschedule_visit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    target_date_str = metadata.get('target_date', "2026-10-15")
    target_reason_sub = metadata.get('target_reason_substring', "Rescheduled per patient request")

    # Retrieve result file
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

    # Scoring initialization
    score = 0
    feedback_parts = []
    
    # 1. Check Document Existence (20 pts)
    # The agent should edit the existing record, not delete and re-create.
    # If they delete and re-create, the ID 'visit_p1_cameron_v1' will likely disappear 
    # unless they manually assigned the exact same ID (unlikely).
    if not result.get('doc_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "The original visit record could not be found. It may have been deleted."
        }
    score += 20
    feedback_parts.append("Original visit record preserved")

    # 2. Check Modification (Anti-gaming) (20 pts)
    initial_rev = result.get('initial_rev')
    current_rev = result.get('current_rev')
    
    if not current_rev or current_rev == initial_rev:
        feedback_parts.append("Document was not modified (revision unchanged).")
        # Fail immediately if no change happened
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
    
    score += 20
    feedback_parts.append("Record was modified")

    # 3. Check Date (40 pts)
    # HospitalRun stores dates as ISO strings (e.g. 2026-10-10T10:00:00.000Z)
    # or sometimes just timestamps depending on how the form saves.
    # We check if the target date string is present in the start_date field.
    start_date = result.get('start_date', '')
    
    if target_date_str in start_date:
        score += 40
        feedback_parts.append(f"Date successfully changed to {target_date_str}")
    else:
        feedback_parts.append(f"Incorrect date. Expected {target_date_str}, got '{start_date}'")

    # 4. Check Reason (20 pts)
    reason = result.get('reason', '')
    if target_reason_sub.lower() in reason.lower():
        score += 20
        feedback_parts.append("Reason updated correctly")
    else:
        feedback_parts.append(f"Reason text missing. Expected '{target_reason_sub}', got '{reason}'")

    # Final Evaluation
    passed = score >= 80  # Requires Date correct + Reason correct + Doc preserved
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }