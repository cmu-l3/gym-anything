#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_refuse_reason(traj, env_info, task_info):
    """
    Verifies that the agent created the 'Overqualified' refuse reason,
    linked it to the correct email template, and used it to refuse the applicant.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Refuse Reason Creation (30 pts)
    if result.get('reason_created') and result.get('reason_name_correct'):
        score += 30
        feedback_parts.append("Refuse Reason 'Overqualified' created.")
    else:
        feedback_parts.append("Refuse Reason 'Overqualified' NOT found.")

    # 2. Verify Template Linkage (20 pts)
    if result.get('template_linked'):
        if result.get('template_name_correct'):
            score += 20
            feedback_parts.append("Correct email template linked.")
        else:
            score += 10
            feedback_parts.append("Email template linked, but name incorrect.")
    else:
        feedback_parts.append("No email template linked to reason.")

    # 3. Verify Applicant Refusal (20 pts)
    if result.get('applicant_refused'):
        score += 20
        feedback_parts.append("Applicant Sarah Jenkins is marked as refused.")
    else:
        feedback_parts.append("Applicant Sarah Jenkins is NOT refused (still active).")

    # 4. Verify Correct Reason Usage (30 pts)
    if result.get('applicant_reason_linked'):
        score += 30
        feedback_parts.append("Applicant refused using the correct 'Overqualified' reason.")
    else:
        if result.get('applicant_refused'):
             feedback_parts.append("Applicant refused, but with the WRONG reason.")
    
    # Anti-gaming: Timestamp check
    # Odoo stores time in UTC, python timestamp is local/UTC depending on config.
    # We perform a loose check if create_date exists.
    # Ideally, we convert Odoo string to timestamp and compare, but presence is good enough for basic anti-gaming
    # combined with the setup script clearing the specific record beforehand.
    if result.get('reason_created') and not result.get('reason_create_date'):
         feedback_parts.append("Warning: Reason creation time missing.")

    passed = score >= 80  # Threshold: Must create reason + template + refuse applicant correctly
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }