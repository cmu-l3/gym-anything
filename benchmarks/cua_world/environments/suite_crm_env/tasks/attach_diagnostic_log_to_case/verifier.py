#!/usr/bin/env python3
"""
Verifier for attach_diagnostic_log_to_case task.

VERIFICATION STRATEGY:
1. Validates Case modification (Status + Priority) using strict DB query state.
2. Validates multi-module relational linkage for Notes (Parent Case UUID + Contact UUID).
3. Validates native file attachment interaction via schema 'filename' check.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_attach_diagnostic_log_to_case(traj, env_info, task_info):
    """
    Main verifier. Uses copy_from_env to safely retrieve the database query outputs 
    exported by the task cleanup script.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    feedback = []

    # Target UUIDs retrieved from export output
    case_id = result.get('case_id', 'MISSING_CASE')
    contact_id = result.get('contact_id', 'MISSING_CONTACT')
    note_id = result.get('note_id', '')

    # 1. Check Case Status Updated (15 pts)
    status = result.get('case_status', '')
    if status == 'Assigned':
        score += 15
        feedback.append("Case status correctly updated to 'Assigned'.")
    else:
        feedback.append(f"Case status is '{status}', expected 'Assigned'.")

    # 2. Check Case Priority Updated (15 pts) - SuiteCRM stores High as 'P1'
    priority = result.get('case_priority', '')
    if priority in ['P1', 'High']:
        score += 15
        feedback.append("Case priority correctly updated to 'High'.")
    else:
        feedback.append(f"Case priority is '{priority}', expected 'P1' (High).")

    # 3. Check Note Created (20 pts)
    if note_id:
        score += 20
        feedback.append("Note 'Client Apache Error Log' found in the database.")
    else:
        feedback.append("Note 'Client Apache Error Log' NOT found.")

    # 4. Check Note Linked to Case (20 pts)
    p_type = result.get('note_parent_type', '')
    p_id = result.get('note_parent_id', '')

    if note_id and p_type == 'Cases' and p_id == case_id and case_id != 'MISSING_CASE':
        score += 20
        feedback.append("Note successfully linked to the target Case parent.")
    else:
        feedback.append("Note is NOT correctly linked to the target Case.")

    # 5. Check Note Linked to Contact (15 pts)
    n_cid = result.get('note_contact_id', '')
    if note_id and n_cid == contact_id and contact_id != 'MISSING_CONTACT':
        score += 15
        feedback.append("Note successfully linked to Contact 'Alice Smith'.")
    else:
        feedback.append("Note is NOT correctly linked to Contact 'Alice Smith'.")

    # 6. Check File Attached (15 pts)
    filename = result.get('note_filename', '')
    if note_id and filename == 'Apache_2k.log':
        score += 15
        feedback.append("File 'Apache_2k.log' correctly attached to the Note.")
    else:
        feedback.append(f"Expected attachment 'Apache_2k.log', found '{filename}'.")

    # Verify Passing Threshold: 70 points AND the Note must exist and be linked to the Case
    key_criteria_met = bool(note_id) and (p_id == case_id)
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }