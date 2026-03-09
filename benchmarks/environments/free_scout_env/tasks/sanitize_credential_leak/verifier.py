#!/usr/bin/env python3
"""
Verifier for sanitize_credential_leak task.

Criteria:
1. Password "ProductionPass2024!" must NOT exist in the note body.
2. Replacement string "[REDACTED]" MUST exist in the note body.
3. The note must NOT be deleted (soft deleted_at must be NULL).
4. The note must have been updated AFTER the task started (anti-gaming).
5. Context verification (optional but good): "postgres://" should still be there.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sanitize_credential_leak(traj, env_info, task_info):
    """
    Verify that the agent redacted the leaked password without deleting the note.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    leaked_password = metadata.get('leaked_password', 'ProductionPass2024!')
    redacted_string = metadata.get('redacted_string', '[REDACTED]')

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

    # Basic Data Check
    if not result.get('thread_found', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target note (thread) not found in database. It may have been permanently deleted."
        }

    body = result.get('body_content', '')
    is_deleted = result.get('is_deleted', False)
    updated_during_task = result.get('updated_during_task', False)

    score = 0
    feedback_parts = []

    # Criterion 1: Password Removed (40 points)
    if leaked_password not in body:
        score += 40
        feedback_parts.append("Sensitive password successfully removed")
    else:
        feedback_parts.append("CRITICAL: Leaked password still present in note")

    # Criterion 2: Redaction Marker Present (30 points)
    # Allow case-insensitive '[redacted]' or simple 'REDACTED'
    if redacted_string in body or "[redacted]" in body.lower():
        score += 30
        feedback_parts.append("Redaction marker present")
    else:
        feedback_parts.append(f"Redaction marker '{redacted_string}' missing")

    # Criterion 3: Note Preserved (Not Deleted) (20 points)
    if not is_deleted:
        score += 20
        feedback_parts.append("Note preserved (not deleted)")
    else:
        feedback_parts.append("Note was deleted (failed preservation requirement)")

    # Criterion 4: Anti-Gaming / Action Verification (10 points)
    # The note must have been modified during the task session
    if updated_during_task:
        score += 10
        feedback_parts.append("Note was updated during task")
    else:
        feedback_parts.append("Note timestamp unchanged (no action taken?)")
        # If the password is still there and timestamp didn't change, they definitely did nothing
        if leaked_password in body:
            return {"passed": False, "score": 0, "feedback": "No changes detected"}

    # Failure Conditions
    # If they deleted the note, they fail the "sanitize not destroy" objective, 
    # even if the password is technically "gone" from view.
    # However, we'll allow partial credit if they deleted it but scoring logic above handles points.
    # Pass threshold: must remove password AND preserve note.
    
    passed = (leaked_password not in body) and (not is_deleted) and (updated_during_task)
    
    # Context check (extra validation, no extra points but good for feedback)
    if "postgres://" not in body:
        feedback_parts.append("Warning: Connection string context seems lost")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }