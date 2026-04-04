#!/usr/bin/env python3
"""
Verifier for cancel_appointment task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cancel_appointment(traj, env_info, task_info):
    """
    Verifies that the appointment was cancelled and the reason was recorded.
    
    Criteria:
    1. Appointment document must still exist (not deleted).
    2. Status must be 'Cancelled' (or 'Canceled').
    3. Notes must contain 'work conflict'.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected metadata
    metadata = task_info.get('metadata', {})
    expected_note_content = metadata.get('expected_note_content', 'work conflict').lower()

    # Retrieve result from container
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

    # Criterion 1: Document Existence (20 points)
    if not result.get('doc_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Appointment document was deleted or not found. You should have cancelled it, not deleted it."
        }
    
    score = 20
    feedback_parts = ["Appointment document exists"]
    
    doc = result.get('doc_content', {})
    # HospitalRun data is often wrapped in a 'data' property
    data = doc.get('data', doc)
    
    # Criterion 2: Status Check (40 points)
    status = data.get('status', '').lower()
    if status in ['cancelled', 'canceled']:
        score += 40
        feedback_parts.append(f"Status is correctly set to '{status}'")
    else:
        feedback_parts.append(f"Incorrect status: expected 'Cancelled', got '{status}'")

    # Criterion 3: Reason in Notes (30 points)
    notes = data.get('notes', '').lower()
    if expected_note_content in notes:
        score += 30
        feedback_parts.append("Cancellation reason found in notes")
    else:
        feedback_parts.append(f"Reason not found in notes. Expected to contain '{expected_note_content}', got '{notes}'")

    # Criterion 4: Anti-gaming / modification check (10 points)
    # If notes are different from original "Regular annual physical"
    original_note = "regular annual physical"
    if notes.strip() != original_note and notes.strip() != "":
        score += 10
        feedback_parts.append("Record was modified")
    else:
        feedback_parts.append("No modification detected in notes")

    # Final Evaluation
    passed = (score >= 90) # Requires status + note + existence
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }