#!/usr/bin/env python3
"""
Verifier for configure_workflow_field_constraints task.

Verification Logic:
1. Parses the JSON result exported from the container.
2. Evaluates the 'db_verification' data extracted via Rails runner.
3. scores based on:
   - Assignee == required (30 pts)
   - Priority == readonly (30 pts)
   - Subject == readonly (30 pts)
   - Description == none/unchanged (10 pts) [Anti-gaming]

Pass Threshold: 90 points (Strict adherence required)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_workflow_field_constraints(traj, env_info, task_info):
    """
    Verifies that the agent correctly configured Redmine workflow permissions.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Framework error: copy_from_env not available"
        }

    # 1. Retrieve Result JSON from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to retrieve or parse task result: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract DB Verification Data
    db_data = result.get('db_verification', {})
    if not db_data or db_data.get('error'):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification script failed: {db_data.get('error', 'Unknown error')}"
        }

    if not db_data.get('valid_setup'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Internal Error: Reference data (Role/Tracker/Status) missing in environment."
        }

    # 3. Score the Result
    score = 0
    feedback_items = []

    # Criterion A: Assignee must be Required (30 pts)
    assignee_rule = db_data.get('assignee_rule', 'none')
    if assignee_rule == 'required':
        score += 30
        feedback_items.append("PASS: Assignee is Required (30/30)")
    else:
        feedback_items.append(f"FAIL: Assignee is '{assignee_rule}', expected 'required' (0/30)")

    # Criterion B: Priority must be Read-only (30 pts)
    priority_rule = db_data.get('priority_rule', 'none')
    if priority_rule == 'readonly':
        score += 30
        feedback_items.append("PASS: Priority is Read-only (30/30)")
    else:
        feedback_items.append(f"FAIL: Priority is '{priority_rule}', expected 'readonly' (0/30)")

    # Criterion C: Subject must be Read-only (30 pts)
    subject_rule = db_data.get('subject_rule', 'none')
    if subject_rule == 'readonly':
        score += 30
        feedback_items.append("PASS: Subject is Read-only (30/30)")
    else:
        feedback_items.append(f"FAIL: Subject is '{subject_rule}', expected 'readonly' (0/30)")

    # Criterion D: Anti-Gaming - Description should be untouched (10 pts)
    # Usually returns 'none' if no rule exists, or sometimes nil depending on version.
    # We accept 'none' or null.
    desc_rule = db_data.get('desc_rule', 'none')
    if desc_rule in ['none', None]:
        score += 10
        feedback_items.append("PASS: Other fields (Description) left untouched (10/10)")
    else:
        feedback_items.append(f"FAIL: Unintended change detected on Description field ('{desc_rule}') (0/10)")

    # 4. Final Verdict
    # Pass threshold is 90 (Requires all 3 main constraints to be correct)
    passed = (score >= 90)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_items)
    }