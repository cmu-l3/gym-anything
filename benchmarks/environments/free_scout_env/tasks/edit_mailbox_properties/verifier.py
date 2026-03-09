#!/usr/bin/env python3
"""
Verifier for edit_mailbox_properties task.

Criteria:
1. Mailbox ID (from setup) must still exist.
2. Mailbox Name must match expected "Field Service Requests".
3. Mailbox Email must match expected "fieldservice@helpdesk.local".
4. Mailbox Aliases must contain "equipmentintake@helpdesk.local".
5. Mailbox count should NOT have increased (ensures edit, not create).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_edit_mailbox_properties(traj, env_info, task_info):
    """Verify that the specific mailbox was edited correctly."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'Field Service Requests')
    expected_email = metadata.get('expected_email', 'fieldservice@helpdesk.local')
    expected_alias = metadata.get('expected_alias', 'equipmentintake@helpdesk.local')

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
    
    # 1. Verify Mailbox Still Exists (Critical)
    if not result.get('mailbox_found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target mailbox ID not found. Did you delete it?"
        }

    # 2. Check Name (30 points)
    current_name = result.get('current_name', '').strip()
    if current_name.lower() == expected_name.lower():
        score += 30
        feedback_parts.append(f"Name updated correctly: '{current_name}'")
    else:
        feedback_parts.append(f"Name mismatch: expected '{expected_name}', got '{current_name}'")

    # 3. Check Email (25 points)
    current_email = result.get('current_email', '').strip()
    if current_email.lower() == expected_email.lower():
        score += 25
        feedback_parts.append(f"Email updated correctly: '{current_email}'")
    else:
        feedback_parts.append(f"Email mismatch: expected '{expected_email}', got '{current_email}'")

    # 4. Check Alias (25 points)
    # Aliases might be JSON ["..."] or comma-separated depending on storage
    current_aliases = result.get('current_aliases', '')
    # Normalize checks
    if expected_alias.lower() in current_aliases.lower():
        score += 25
        feedback_parts.append(f"Alias found: '{expected_alias}'")
    else:
        feedback_parts.append(f"Alias missing. Current aliases: '{current_aliases}'")

    # 5. Anti-Gaming: Check Count (20 points)
    # If count increased, they likely created a new mailbox instead of editing
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))
    
    if current_count == initial_count:
        score += 20
        feedback_parts.append("Mailbox count unchanged (Edit confirmed)")
    elif current_count > initial_count:
        feedback_parts.append("Mailbox count INCREASED. You must EDIT the existing mailbox, not create a new one.")
    else:
        # Count decreased? Maybe deleted others. Acceptable if target is correct.
        score += 20
        feedback_parts.append("Mailbox count decreased (Edit confirmed)")

    # Pass threshold
    # Must have name AND email correct to pass substantially
    # 55 points required
    passed = score >= 55 and (current_name.lower() == expected_name.lower())

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }