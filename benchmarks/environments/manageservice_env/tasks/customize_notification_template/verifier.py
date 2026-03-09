#!/usr/bin/env python3
"""
Verifier for customize_notification_template task.

Checks if the ServiceDesk Plus notification template for "Request Received"
has been updated with the required Subject and Body text.
"""

import json
import os
import re
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_notification_template(traj, env_info, task_info):
    """
    Verifies that the notification template was updated correctly.
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

    metadata = task_info.get('metadata', {})
    expected_subject = metadata.get('expected_subject_string', 'Global Corp')
    expected_body = metadata.get('expected_body_string', '555-0199')
    
    db_records = result.get('db_records', '')
    
    score = 0
    feedback = []
    
    # Analyze DB Records
    # The shell script exports rows. We check if ANY row matches our criteria.
    # We are looking for a row that contains the subject AND body changes ideally,
    # or at least the specific changes in the table.
    
    has_subject_change = expected_subject in db_records
    has_body_change = expected_body in db_records
    
    # Check for variable presence (e.g. $RequestId)
    # The user might use different variables depending on version ($WOID, $RequestId, etc)
    # We look for a pattern like $...Id or similar in the same record that has Global Corp
    has_variable = False
    if has_subject_change:
        # Simple regex check on the whole db dump for the combination
        # Looking for line containing 'Global Corp' AND ('$' or something resembling a variable)
        for line in db_records.split('\n'):
            if expected_subject in line:
                if re.search(r'\$[a-zA-Z]+', line) or re.search(r'##[a-zA-Z]+##', line):
                    has_variable = True
                    break

    # Check for rule enabled
    # The SQL query tried to pull 'status'. Usually 'true', 'active', or '1'.
    # If the record matching our text also has 'true' or 'ACTIVE', we give points.
    rule_enabled = False
    if "true" in db_records.lower() or "active" in db_records.lower():
         rule_enabled = True
    
    # Scoring
    if has_subject_change:
        score += 30
        feedback.append("Subject updated with 'Global Corp'.")
    else:
        feedback.append("Subject NOT updated correctly (missing 'Global Corp').")

    if has_variable:
        score += 20
        feedback.append("Subject includes dynamic variable.")
    elif has_subject_change:
        feedback.append("Subject missing dynamic variable (e.g. $RequestId).")

    if has_body_change:
        score += 30
        feedback.append("Body updated with '555-0199'.")
    else:
        feedback.append("Body text missing emergency hotline number.")

    if rule_enabled:
        score += 20
        feedback.append("Notification rule appears enabled.")
    else:
        # If we can't definitively determine status from simple grep, but changes exist,
        # we might give benefit of doubt or fail.
        # However, for this task, if they modified it, it's likely active unless they explicitly disabled it.
        # We'll check if we found the record at all.
        if has_subject_change or has_body_change:
            feedback.append("Could not verify rule status (check screenshot), but content is present.")
            score += 10 # Partial credit
        else:
            feedback.append("Rule check failed.")

    passed = (score >= 70) and has_body_change
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }